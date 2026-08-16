import AppKit
import OpenConnectCore
import SwiftUI

private struct MenuBarContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDetails = false
    @State private var collapsedContentHeight: CGFloat = 669

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 14) {
                    header
                    statusCard
                    configurationCard

                    if model.isAwaitingMFA {
                        mfaCard
                    }

                    if model.openConnectPath == nil {
                        dependencyCard
                    }

                    controls

                    if let notice = model.notice {
                        noticeView(notice)
                    }

                    details
                    footer
                }
                .padding(18)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: MenuBarContentHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(!showDetails && collapsedContentHeight <= preferredWindowHeight)
        }
        .frame(width: 380, height: preferredWindowHeight)
        .onPreferenceChange(MenuBarContentHeightKey.self) { contentHeight in
            guard !showDetails, contentHeight > 0 else { return }
            collapsedContentHeight = ceil(contentHeight) + 8
        }
        .preferredColorScheme(nil)
    }

    private var preferredWindowHeight: CGFloat {
        let visibleScreenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let maximumHeight = min(max(visibleScreenHeight - 48, 600), 900)
        return min(max(collapsedContentHeight, 600), maximumHeight)
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            Circle()
                .fill(Color.blue.opacity(0.17))
                .frame(width: 260, height: 260)
                .blur(radius: 55)
                .offset(x: -145, y: -245)

            Circle()
                .fill(Color.cyan.opacity(0.11))
                .frame(width: 210, height: 210)
                .blur(radius: 58)
                .offset(x: 165, y: 235)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.95), .cyan.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .shadow(color: .blue.opacity(0.25), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenConnect VPN")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(L10n.text("app.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(model.phase.tint)
                .frame(width: 9, height: 9)
                .shadow(color: model.phase.tint.opacity(0.55), radius: 5)
                .accessibilityLabel(model.phase.title)
        }
        .padding(.horizontal, 2)
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(model.phase.tint.opacity(0.14))
                Image(systemName: model.phase.symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(model.phase.tint)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.phase.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(model.phaseDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vpnGlassCard()
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(L10n.text("section.connection"), systemImage: "network")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("field.portal.label"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "globe.europe.africa.fill")
                        .foregroundStyle(.blue)
                    TextField(L10n.text("field.portal.placeholder"), text: $model.portalAddress)
                        .textFieldStyle(.plain)
                        .disabled(model.phase.isBusy || model.phase.isConnected)
                        .onSubmit { if model.canConnect { model.connect() } }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("field.username.label"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.blue)
                    TextField(L10n.text("field.browser.placeholder"), text: $model.username)
                        .textFieldStyle(.plain)
                        .disabled(model.phase.isBusy || model.phase.isConnected)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("field.password.label"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.blue)
                    SecureField(L10n.text("field.browser.placeholder"), text: $model.password)
                        .textFieldStyle(.plain)
                        .disabled(model.phase.isBusy || model.phase.isConnected)
                        .onSubmit { if model.canConnect { model.connect() } }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            Toggle(
                isOn: Binding(
                    get: { model.rememberPassword },
                    set: { model.setRememberPassword($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("toggle.remember.title"))
                        .font(.system(size: 13, weight: .medium))
                    Text(
                        model.hasStoredPassword
                            ? L10n.text("toggle.remember.stored")
                            : L10n.text("toggle.remember.description")
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(model.phase.isBusy || model.phase.isConnected)

            Divider().opacity(0.5)

            Toggle(
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("toggle.login.title"))
                        .font(.system(size: 13, weight: .medium))
                    Text(L10n.text("toggle.login.description"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vpnGlassCard()
    }

    private var mfaCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(L10n.text("mfa.title"), systemImage: "checkmark.shield.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)

            if let prompt = model.authenticationChallenge {
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "number")
                    .foregroundStyle(.orange)
                SecureField(L10n.text("mfa.placeholder"), text: $model.mfaCode)
                    .textFieldStyle(.plain)
                    .onSubmit { if model.canSubmitMFA { model.submitMFA() } }
                Button(L10n.text("button.confirm")) {
                    model.submitMFA()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canSubmitMFA)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vpnGlassCard()
    }

    private var dependencyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.text("dependency.title"), systemImage: "shippingbox.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text(L10n.text("dependency.description"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(L10n.text("button.copy_brew")) {
                    model.copyHomebrewCommand()
                }
                Button(L10n.text("button.recheck")) {
                    model.refreshOpenConnect()
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vpnGlassCard()
    }

    private var controls: some View {
        Group {
            if model.canCancelAuthentication {
                Button {
                    model.cancelConnection()
                } label: {
                    Label(L10n.text("button.cancel"), systemImage: "xmark")
                }
                .buttonStyle(VPNPrimaryButtonStyle(tint: .secondary))
            } else if model.phase.isBusy {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.phase.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                Button {
                    model.performPrimaryAction()
                } label: {
                    Label(model.primaryButtonTitle, systemImage: model.primaryButtonSymbol)
                }
                .buttonStyle(VPNPrimaryButtonStyle(tint: model.phase.isConnected ? .red : .blue))
                .disabled(!model.phase.isConnected && !model.canConnect)
                .opacity((!model.phase.isConnected && !model.canConnect) ? 0.5 : 1)
            }
        }
    }

    private func noticeView(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text(notice)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var details: some View {
        DisclosureGroup(L10n.text("details.title"), isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: 8) {
                if let path = model.openConnectPath {
                    Label(path, systemImage: "terminal.fill")
                        .textSelection(.enabled)
                } else {
                    Label(L10n.text("details.openconnect_missing"), systemImage: "terminal")
                }

                if model.recentLogs.isEmpty {
                    Text(L10n.text("details.no_events"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.recentLogs.suffix(8).joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if model.launchAtLogin {
                    Button(L10n.text("button.open_login_items")) {
                        model.openLoginItemSettings()
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.caption2)
            .padding(.top, 8)
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            Label(
                model.hasStoredPassword
                    ? L10n.text("footer.password.secure")
                    : model.rememberPassword
                        ? L10n.text("footer.password.pending")
                        : L10n.text("footer.password.not_stored"),
                systemImage: model.rememberPassword ? "key.fill" : "lock.fill"
            )
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Button(L10n.text("button.quit")) {
                model.quit()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 2)
    }
}
