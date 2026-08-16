import SwiftUI
import OpenConnectCore

enum ConnectionPhase: Equatable {
    case inactive
    case authenticating
    case authorizing
    case connecting
    case connected
    case disconnecting
    case failed(String)

    var title: String {
        switch self {
        case .inactive:
            return L10n.text("phase.inactive.title")
        case .authenticating:
            return L10n.text("phase.authenticating.title")
        case .authorizing:
            return L10n.text("phase.authorizing.title")
        case .connecting:
            return L10n.text("phase.connecting.title")
        case .connected:
            return L10n.text("phase.connected.title")
        case .disconnecting:
            return L10n.text("phase.disconnecting.title")
        case .failed:
            return L10n.text("phase.failed.title")
        }
    }

    var detail: String {
        switch self {
        case .inactive:
            return L10n.text("phase.inactive.detail")
        case .authenticating:
            return L10n.text("phase.authenticating.detail")
        case .authorizing:
            return L10n.text("phase.authorizing.detail")
        case .connecting:
            return L10n.text("phase.connecting.detail")
        case .connected:
            return L10n.text("phase.connected.detail")
        case .disconnecting:
            return L10n.text("phase.disconnecting.detail")
        case .failed(let message):
            return message
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .connected:
            return "lock.shield.fill"
        case .authenticating, .authorizing, .connecting, .disconnecting:
            return "lock.shield"
        case .failed:
            return "exclamationmark.shield.fill"
        case .inactive:
            return "shield.slash"
        }
    }

    var symbol: String {
        switch self {
        case .connected:
            return "checkmark.shield.fill"
        case .authenticating:
            return "person.badge.key.fill"
        case .authorizing:
            return "lock.open.fill"
        case .connecting, .disconnecting:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.shield.fill"
        case .inactive:
            return "shield.slash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .connected:
            return .green
        case .authenticating, .authorizing, .connecting, .disconnecting:
            return .orange
        case .failed:
            return .red
        case .inactive:
            return .secondary
        }
    }

    var isBusy: Bool {
        switch self {
        case .authenticating, .authorizing, .connecting, .disconnecting:
            return true
        default:
            return false
        }
    }

    var isConnected: Bool {
        self == .connected
    }
}
