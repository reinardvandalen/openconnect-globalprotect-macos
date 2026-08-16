import AppKit
import Foundation
import OpenConnectCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var portalAddress: String {
        didSet { UserDefaults.standard.set(portalAddress, forKey: Keys.portalAddress) }
    }

    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Keys.username) }
    }

    @Published var password = ""
    @Published private(set) var rememberPassword = false
    @Published private(set) var hasStoredPassword = false
    @Published var mfaCode = ""
    @Published private(set) var authenticationChallenge: String?

    @Published private(set) var phase: ConnectionPhase = .inactive
    @Published private(set) var openConnectPath: String?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var recentLogs: [String] = []
    @Published var notice: String?

    private let service = VPNService()
    private let passwordStore: KeychainPasswordStore
    private var connectionTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var wasConnected = false
    private var usesPasswordAuthentication = false

    private enum Keys {
        static let portalAddress = "portalAddress"
        static let username = "username"
        static let rememberPassword = "rememberPassword"
    }

    init(passwordStore: KeychainPasswordStore = KeychainPasswordStore()) {
        self.passwordStore = passwordStore
        portalAddress = UserDefaults.standard.string(forKey: Keys.portalAddress) ?? ""
        username = UserDefaults.standard.string(forKey: Keys.username) ?? ""
        rememberPassword = UserDefaults.standard.bool(forKey: Keys.rememberPassword)
        if rememberPassword {
            do {
                if let savedPassword = try passwordStore.load() {
                    password = savedPassword
                    hasStoredPassword = true
                }
            } catch {
                rememberPassword = false
                UserDefaults.standard.set(false, forKey: Keys.rememberPassword)
                notice = "Het bewaarde wachtwoord kon niet worden geladen: \(error.localizedDescription)"
            }
        }
        openConnectPath = service.locateOpenConnect()
        refreshLaunchAtLogin()
        refreshConnectionState()

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                self?.refreshConnectionState()
            }
        }
    }

    deinit {
        monitorTask?.cancel()
        connectionTask?.cancel()
    }

    var canConnect: Bool {
        !portalAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            openConnectPath != nil &&
            (password.isEmpty || !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
            !phase.isBusy
    }

    var isAwaitingMFA: Bool {
        authenticationChallenge != nil
    }

    var canSubmitMFA: Bool {
        isAwaitingMFA && !mfaCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var phaseDetail: String {
        guard phase == .authenticating else { return phase.detail }
        if isAwaitingMFA {
            return "Vul de verificatiecode in om de aanmelding af te ronden."
        }
        return usesPasswordAuthentication
            ? "Je inloggegevens worden gecontroleerd."
            : "Rond het inloggen af in je standaardbrowser."
    }

    var primaryButtonTitle: String {
        phase.isConnected ? "Verbreek VPN" : "Verbind met VPN"
    }

    var primaryButtonSymbol: String {
        phase.isConnected ? "stop.fill" : "play.fill"
    }

    var canCancelAuthentication: Bool {
        phase == .authenticating
    }

    func performPrimaryAction() {
        if phase.isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    func connect() {
        guard connectionTask == nil else { return }

        let endpoint: URL
        do {
            endpoint = try VPNEndpoint.normalize(portalAddress)
            portalAddress = endpoint.absoluteString
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        guard let binary = service.locateOpenConnect() else {
            openConnectPath = nil
            phase = .failed("Installeer OpenConnect eerst via Homebrew.")
            return
        }

        openConnectPath = binary
        notice = nil
        authenticationChallenge = nil
        mfaCode = ""
        let submittedPassword = password.isEmpty ? nil : password
        usesPasswordAuthentication = submittedPassword != nil
        if !rememberPassword {
            password = ""
        }
        appendLog("Authenticatie gestart voor \(endpoint.host ?? endpoint.absoluteString).")
        phase = .authenticating

        connectionTask = Task { [weak self] in
            guard let self else { return }

            do {
                let authentication = try await service.authenticate(
                    binary: binary,
                    endpoint: endpoint,
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: submittedPassword,
                    challengeHandler: { [weak self] prompt in
                        Task { @MainActor in
                            self?.authenticationChallenge = prompt
                            self?.appendLog("De portal vraagt om aanvullende beveiligde invoer.")
                        }
                    },
                    logHandler: { [weak self] message in
                        Task { @MainActor in self?.appendLog(message) }
                    }
                )

                guard !Task.isCancelled else { throw CancellationError() }
                rememberPasswordIfNeeded(submittedPassword)
                phase = .authorizing
                authenticationChallenge = nil
                mfaCode = ""
                appendLog("Authenticatie voltooid. De tunnel wacht op macOS-toestemming.")

                try await service.startTunnel(
                    binary: binary,
                    authentication: authentication,
                    logHandler: { [weak self] message in
                        Task { @MainActor in self?.appendLog(message) }
                    }
                )

                guard !Task.isCancelled else { throw CancellationError() }
                phase = .connected
                wasConnected = true
                appendLog("De VPN-tunnel is actief.")
            } catch is CancellationError {
                phase = .inactive
                appendLog("Verbinden geannuleerd.")
            } catch VPNServiceError.authenticationCancelled {
                phase = .inactive
                appendLog("Verbinden geannuleerd.")
            } catch {
                phase = .failed(error.localizedDescription)
                appendLog("Fout: \(error.localizedDescription)")
            }

            connectionTask = nil
            authenticationChallenge = nil
            mfaCode = ""
        }
    }

    func submitMFA() {
        let response = mfaCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else { return }

        do {
            try service.submitAuthenticationResponse(response)
            mfaCode = ""
            authenticationChallenge = nil
            appendLog("MFA-code doorgegeven; de portal controleert de code.")
        } catch {
            notice = error.localizedDescription
            appendLog("Fout: \(error.localizedDescription)")
        }
    }

    func cancelConnection() {
        guard canCancelAuthentication else { return }
        service.cancelAuthentication()
        connectionTask?.cancel()
        connectionTask = nil
        authenticationChallenge = nil
        mfaCode = ""
        phase = .inactive
        appendLog("Verbinden geannuleerd.")
    }

    func disconnect(afterDisconnect: (() -> Void)? = nil) {
        guard !phase.isBusy else { return }
        phase = .disconnecting
        notice = nil

        connectionTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await service.stopTunnel()
                phase = .inactive
                wasConnected = false
                appendLog("De VPN-tunnel is afgesloten.")
                afterDisconnect?()
            } catch {
                phase = .failed(error.localizedDescription)
                appendLog("Fout: \(error.localizedDescription)")
            }

            connectionTask = nil
        }
    }

    func refreshOpenConnect() {
        openConnectPath = service.locateOpenConnect()
        if openConnectPath != nil, case .failed = phase {
            phase = .inactive
        }
    }

    func copyHomebrewCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install openconnect", forType: .string)
        notice = "Installatiecommando gekopieerd."
    }

    func setRememberPassword(_ enabled: Bool) {
        guard enabled != rememberPassword else { return }
        notice = nil

        if enabled {
            do {
                if password.isEmpty, let savedPassword = try passwordStore.load() {
                    password = savedPassword
                    hasStoredPassword = true
                }
                rememberPassword = true
                UserDefaults.standard.set(true, forKey: Keys.rememberPassword)
                if password.isEmpty {
                    notice = "Het wachtwoord wordt na een succesvolle aanmelding in macOS Sleutelhanger bewaard."
                }
            } catch {
                rememberPassword = false
                UserDefaults.standard.set(false, forKey: Keys.rememberPassword)
                notice = "Wachtwoord onthouden kon niet worden ingeschakeld: \(error.localizedDescription)"
            }
            return
        }

        do {
            try passwordStore.delete()
            rememberPassword = false
            hasStoredPassword = false
            UserDefaults.standard.set(false, forKey: Keys.rememberPassword)
            notice = "Het bewaarde wachtwoord is uit macOS Sleutelhanger verwijderd."
        } catch {
            notice = "Het bewaarde wachtwoord kon niet worden verwijderd: \(error.localizedDescription)"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLogin()

            if SMAppService.mainApp.status == .requiresApproval {
                notice = "Sta de app nog toe bij Systeeminstellingen, Algemeen, Inloggen en extensies."
            } else {
                notice = nil
            }
        } catch {
            refreshLaunchAtLogin()
            notice = "Opstartinstelling kon niet worden gewijzigd: \(error.localizedDescription)"
        }
    }

    func openLoginItemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func quit() {
        if service.isTunnelRunning {
            disconnect {
                NSApplication.shared.terminate(nil)
            }
        } else {
            service.cancelAuthentication()
            NSApplication.shared.terminate(nil)
        }
    }

    private func refreshConnectionState() {
        let isRunning = service.isTunnelRunning

        if isRunning {
            wasConnected = true
            if phase != .connected && phase != .disconnecting {
                phase = .connected
                appendLog("De actieve VPN-tunnel is gedetecteerd.")
            }
        } else if wasConnected && !phase.isBusy {
            wasConnected = false
            phase = .failed("De VPN-verbinding is onverwacht verbroken.")
            appendLog("OpenConnect is niet meer actief.")
        }
    }

    private func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
    }

    private func rememberPasswordIfNeeded(_ submittedPassword: String?) {
        guard rememberPassword,
              let submittedPassword,
              !submittedPassword.isEmpty else {
            return
        }

        do {
            try passwordStore.save(submittedPassword)
            password = submittedPassword
            hasStoredPassword = true
            appendLog("Het wachtwoord is beveiligd opgeslagen in macOS Sleutelhanger.")
        } catch {
            notice = "Het wachtwoord kon niet worden bewaard: \(error.localizedDescription)"
            appendLog("Het wachtwoord kon niet in macOS Sleutelhanger worden bewaard.")
        }
    }

    private func appendLog(_ message: String) {
        let sanitized = LogSanitizer.sanitize(message)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        recentLogs.append("\(formatter.string(from: Date()))  \(sanitized)")
        if recentLogs.count > 40 {
            recentLogs.removeFirst(recentLogs.count - 40)
        }
    }
}
