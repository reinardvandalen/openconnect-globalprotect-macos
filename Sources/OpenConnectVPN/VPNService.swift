import AppKit
import Darwin
import Foundation
import OpenConnectCore

enum VPNServiceError: LocalizedError {
    case openConnectMissing
    case launcherMissing
    case authenticationFailed(String)
    case authenticationCancelled
    case authenticationInputUnavailable
    case authorizationCancelled
    case privilegedCommandFailed(String)
    case tunnelDidNotStart
    case tunnelDidNotStop
    case supportDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .openConnectMissing:
            return "OpenConnect is niet gevonden. Installeer het met ‘brew install openconnect’."
        case .launcherMissing:
            return "De beveiligde tunnelstarter ontbreekt. Installeer OpenConnect VPN opnieuw."
        case .authenticationFailed(let detail):
            return detail.isEmpty
                ? "Inloggen bij GlobalProtect is mislukt."
                : "Inloggen is mislukt: \(detail)"
        case .authenticationCancelled:
            return "Het inloggen is geannuleerd."
        case .authenticationInputUnavailable:
            return "De verificatiecode kon niet aan OpenConnect worden doorgegeven."
        case .authorizationCancelled:
            return "De macOS-toestemming is geannuleerd."
        case .privilegedCommandFailed(let detail):
            return detail.isEmpty
                ? "macOS kon de VPN-opdracht niet uitvoeren."
                : "De VPN-opdracht is mislukt: \(detail)"
        case .tunnelDidNotStart:
            return "OpenConnect meldde succes, maar de VPN-tunnel werd niet actief."
        case .tunnelDidNotStop:
            return "OpenConnect kon de VPN-tunnel niet volledig afsluiten."
        case .supportDirectoryUnavailable:
            return "De beveiligde werkmap van de app kon niet worden gemaakt."
        }
    }
}

final class VPNService: @unchecked Sendable {
    typealias LogHandler = @Sendable (String) -> Void

    private let processLock = NSLock()
    private var authenticationProcess: Process?
    private var authenticationInput: FileHandle?
    private var cancellationRequested = false

    private var supportDirectory: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return base.appendingPathComponent("OpenConnectVPN", isDirectory: true)
    }

    private var pidFileURL: URL? {
        supportDirectory?.appendingPathComponent("openconnect.pid")
    }

    var isTunnelRunning: Bool {
        guard let pid = currentPID() else { return false }
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    func locateOpenConnect() -> String? {
        let candidates = [
            "/opt/homebrew/bin/openconnect",
            "/usr/local/bin/openconnect",
            "/opt/local/sbin/openconnect",
            "/opt/local/bin/openconnect"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func authenticate(
        binary: String,
        endpoint: URL,
        username: String,
        password: String?,
        challengeHandler: @escaping LogHandler,
        logHandler: @escaping LogHandler
    ) async throws -> AuthenticationResult {
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw VPNServiceError.openConnectMissing
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                do {
                    let result = try self.runAuthentication(
                        binary: binary,
                        endpoint: endpoint,
                        username: username,
                        password: password,
                        challengeHandler: challengeHandler,
                        logHandler: logHandler
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cancelAuthentication() {
        processLock.lock()
        cancellationRequested = true
        let process = authenticationProcess
        let input = authenticationInput
        authenticationInput = nil
        processLock.unlock()

        try? input?.close()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func submitAuthenticationResponse(_ response: String) throws {
        processLock.lock()
        let input = authenticationInput
        let isRunning = authenticationProcess?.isRunning == true
        processLock.unlock()

        guard isRunning, let input else {
            throw VPNServiceError.authenticationInputUnavailable
        }

        do {
            try input.write(contentsOf: Data("\(response)\n".utf8))
        } catch {
            throw VPNServiceError.authenticationInputUnavailable
        }
    }

    func startTunnel(
        binary: String,
        authentication: AuthenticationResult,
        logHandler: @escaping LogHandler
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                do {
                    try self.startTunnelSynchronously(
                        binary: binary,
                        authentication: authentication,
                        logHandler: logHandler
                    )
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopTunnel() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                do {
                    try self.stopTunnelSynchronously()
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runAuthentication(
        binary: String,
        endpoint: URL,
        username: String,
        password: String?,
        challengeHandler: @escaping LogHandler,
        logHandler: @escaping LogHandler
    ) throws -> AuthenticationResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let standardInput = password == nil ? nil : Pipe()
        let output = ProcessOutput()

        process.executableURL = URL(fileURLWithPath: binary)
        var arguments = [
            "--protocol=gp",
            "--authenticate",
            "--external-browser=/usr/bin/open",
            "--os=mac-intel",
            "--timestamp"
        ]
        if password == nil {
            arguments.append("--non-inter")
        } else {
            arguments.append("--passwd-on-stdin")
        }
        if !username.isEmpty {
            arguments.append("--user=\(username)")
        }
        arguments.append(endpoint.absoluteString)

        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.standardInput = standardInput ?? FileHandle.nullDevice
        process.environment = processEnvironment()

        processLock.lock()
        cancellationRequested = false
        authenticationProcess = process
        authenticationInput = standardInput?.fileHandleForWriting
        processLock.unlock()

        do {
            try process.run()
        } catch {
            clearAuthenticationProcess()
            throw error
        }

        if let password, let input = standardInput?.fileHandleForWriting {
            do {
                try input.write(contentsOf: Data("\(password)\n".utf8))
            } catch {
                process.terminate()
                clearAuthenticationProcess()
                throw VPNServiceError.authenticationInputUnavailable
            }
            logHandler("OpenConnect controleert de gebruikersnaam en het wachtwoord.")
        } else {
            logHandler("OpenConnect heeft de portal bereikt. Rond MFA af in de browser.")
        }

        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
            output.setStandardOutput(data)
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            var detector = AuthenticationPromptDetector()
            while true {
                let data = standardError.fileHandleForReading.availableData
                guard !data.isEmpty else { break }
                output.appendStandardError(data)

                guard password != nil else { continue }

                for prompt in detector.append(String(decoding: data, as: UTF8.self)) {
                    switch prompt {
                    case .gateway(let gateway):
                        do {
                            try standardInput?.fileHandleForWriting.write(
                                contentsOf: Data("\(gateway)\n".utf8)
                            )
                            logHandler("OpenConnect heeft automatisch de enige beschikbare gateway gekozen.")
                        } catch {
                            process.terminate()
                        }
                    case .password:
                        challengeHandler("De portal vraagt het wachtwoord opnieuw. Controleer je inloggegevens.")
                    case .verification:
                        challengeHandler("Voer de Google Authenticator-code in.")
                    }
                }
            }
            readGroup.leave()
        }

        process.waitUntilExit()
        readGroup.wait()

        processLock.lock()
        let wasCancelled = cancellationRequested
        authenticationProcess = nil
        let input = authenticationInput
        authenticationInput = nil
        cancellationRequested = false
        processLock.unlock()
        try? input?.close()

        if wasCancelled {
            throw VPNServiceError.authenticationCancelled
        }

        let snapshot = output.snapshot()
        let stderr = LogSanitizer.sanitize(String(decoding: snapshot.standardError, as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw VPNServiceError.authenticationFailed(Self.shortened(stderr))
        }

        let stdout = String(decoding: snapshot.standardOutput, as: UTF8.self)
        if !stderr.isEmpty {
            logHandler(Self.shortened(stderr))
        }
        return try AuthenticationResult.parse(stdout)
    }

    private func startTunnelSynchronously(
        binary: String,
        authentication: AuthenticationResult,
        logHandler: @escaping LogHandler
    ) throws {
        guard let directory = supportDirectory, let pidFile = pidFileURL else {
            throw VPNServiceError.supportDirectoryUnavailable
        }
        guard let launcher = locateLauncher() else {
            throw VPNServiceError.launcherMissing
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let cookieFile = directory.appendingPathComponent("auth-\(UUID().uuidString).cookie")
        try Data(authentication.cookie.utf8).write(to: cookieFile, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: cookieFile.path
        )

        defer {
            try? FileManager.default.removeItem(at: cookieFile)
        }

        var openConnectArguments = [
            "--protocol=gp",
            "--cookie-on-stdin",
            "--background",
            "--pid-file=\(pidFile.path)",
            "--syslog",
            "--os=mac-intel",
            "--reconnect-timeout=300",
            "--force-dpd=30"
        ]

        if let fingerprint = authentication.fingerprint {
            openConnectArguments.append("--servercert=\(fingerprint)")
        }
        if let resolve = authentication.resolve {
            openConnectArguments.append("--resolve=\(resolve)")
        }
        openConnectArguments.append(authentication.connectURL)

        let quotedArguments = ([binary] + openConnectArguments)
            .map(ShellEscaping.quote)
            .joined(separator: " ")
        let command = """
        /bin/rm -f \(ShellEscaping.quote(pidFile.path)); \
        if /bin/cat \(ShellEscaping.quote(cookieFile.path)) | \(ShellEscaping.quote(launcher)) \(quotedArguments) >/dev/null 2>&1; then \
          /bin/rm -f \(ShellEscaping.quote(cookieFile.path)); \
          exit 0; \
        else \
          result=$?; \
          /bin/rm -f \(ShellEscaping.quote(cookieFile.path)) \(ShellEscaping.quote(pidFile.path)); \
          exit $result; \
        fi
        """

        logHandler("macOS controleert de toestemming voor netwerkbeheer.")
        try runWithAdministratorPrivileges(command)

        for _ in 0..<30 {
            if isTunnelRunning { return }
            usleep(100_000)
        }
        throw VPNServiceError.tunnelDidNotStart
    }

    private func stopTunnelSynchronously() throws {
        guard let pidFile = pidFileURL else {
            throw VPNServiceError.supportDirectoryUnavailable
        }

        guard isTunnelRunning else {
            return
        }

        let command = TunnelStopCommand.make(pidFilePath: pidFile.path)

        try runWithAdministratorPrivileges(command)
        guard !isTunnelRunning else {
            throw VPNServiceError.tunnelDidNotStop
        }
    }

    private func runWithAdministratorPrivileges(_ command: String) throws {
        let source = "do shell script \"\(ShellEscaping.appleScriptString(command))\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            throw VPNServiceError.privilegedCommandFailed("")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return }
        let code = errorInfo[NSAppleScript.errorNumber] as? Int
        if code == -128 {
            throw VPNServiceError.authorizationCancelled
        }

        let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? ""
        throw VPNServiceError.privilegedCommandFailed(Self.shortened(message))
    }

    private func locateLauncher() -> String? {
        guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            return nil
        }

        let launcher = executableDirectory.appendingPathComponent("OpenConnectLauncher").path
        return FileManager.default.isExecutableFile(atPath: launcher) ? launcher : nil
    }

    private func currentPID() -> Int32? {
        guard let pidFile = pidFileURL,
              let contents = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 1 else {
            return nil
        }
        return pid
    }

    private func clearAuthenticationProcess() {
        processLock.lock()
        authenticationProcess = nil
        let input = authenticationInput
        authenticationInput = nil
        cancellationRequested = false
        processLock.unlock()
        try? input?.close()
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        environment["BROWSER"] = "/usr/bin/open"
        return environment
    }

    private static func shortened(_ text: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .suffix(8)
            .map(String.init)
        return lines.joined(separator: " ").prefix(1_000).description
    }
}

private final class ProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = Data()
    private var standardError = Data()

    func setStandardOutput(_ data: Data) {
        lock.lock()
        standardOutput = data
        lock.unlock()
    }

    func appendStandardError(_ data: Data) {
        lock.lock()
        standardError.append(data)
        lock.unlock()
    }

    func snapshot() -> (standardOutput: Data, standardError: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (standardOutput, standardError)
    }
}
