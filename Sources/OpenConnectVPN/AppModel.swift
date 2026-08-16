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
                notice = L10n.format("notice.password_load_failed", error.localizedDescription)
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
            return L10n.text("auth.mfa.detail")
        }
        return usesPasswordAuthentication
            ? L10n.text("auth.credentials_checking")
            : L10n.text("auth.browser_continue")
    }

    var primaryButtonTitle: String {
        phase.isConnected ? L10n.text("button.disconnect") : L10n.text("button.connect")
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
            phase = .failed(L10n.text("error.install_openconnect"))
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
        appendLog(L10n.format("log.authentication_started", endpoint.host ?? endpoint.absoluteString))
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
                            self?.appendLog(L10n.text("log.portal_secure_input"))
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
                appendLog(L10n.text("log.authentication_complete"))

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
                appendLog(L10n.text("log.tunnel_active"))
            } catch is CancellationError {
                phase = .inactive
                appendLog(L10n.text("log.connection_cancelled"))
            } catch VPNServiceError.authenticationCancelled {
                phase = .inactive
                appendLog(L10n.text("log.connection_cancelled"))
            } catch {
                phase = .failed(error.localizedDescription)
                appendLog(L10n.format("log.error", error.localizedDescription))
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
            appendLog(L10n.text("log.mfa_submitted"))
        } catch {
            notice = error.localizedDescription
            appendLog(L10n.format("log.error", error.localizedDescription))
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
        appendLog(L10n.text("log.connection_cancelled"))
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
                appendLog(L10n.text("log.tunnel_stopped"))
                afterDisconnect?()
            } catch {
                phase = .failed(error.localizedDescription)
                appendLog(L10n.format("log.error", error.localizedDescription))
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
        notice = L10n.text("notice.install_command_copied")
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
                    notice = L10n.text("notice.password_save_pending")
                }
            } catch {
                rememberPassword = false
                UserDefaults.standard.set(false, forKey: Keys.rememberPassword)
                notice = L10n.format("notice.remember_enable_failed", error.localizedDescription)
            }
            return
        }

        do {
            try passwordStore.delete()
            rememberPassword = false
            hasStoredPassword = false
            UserDefaults.standard.set(false, forKey: Keys.rememberPassword)
            notice = L10n.text("notice.password_removed")
        } catch {
            notice = L10n.format("notice.password_remove_failed", error.localizedDescription)
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
                notice = L10n.text("notice.login_item_approval")
            } else {
                notice = nil
            }
        } catch {
            refreshLaunchAtLogin()
            notice = L10n.format("notice.login_item_failed", error.localizedDescription)
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
                appendLog(L10n.text("log.active_tunnel_detected"))
            }
        } else if wasConnected && !phase.isBusy {
            wasConnected = false
            phase = .failed(L10n.text("error.connection_lost"))
            appendLog(L10n.text("log.openconnect_inactive"))
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
            appendLog(L10n.text("log.password_saved"))
        } catch {
            notice = L10n.format("notice.password_save_failed", error.localizedDescription)
            appendLog(L10n.text("log.password_save_failed"))
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
