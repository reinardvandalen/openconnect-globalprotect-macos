import SwiftUI

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
            return "Niet verbonden"
        case .authenticating:
            return "Inloggen met MFA"
        case .authorizing:
            return "Toestemming nodig"
        case .connecting:
            return "VPN verbinden"
        case .connected:
            return "VPN actief"
        case .disconnecting:
            return "Verbinding verbreken"
        case .failed:
            return "Verbinding mislukt"
        }
    }

    var detail: String {
        switch self {
        case .inactive:
            return "Je internetverkeer loopt niet via GlobalProtect."
        case .authenticating:
            return "Rond het inloggen af in je standaardbrowser."
        case .authorizing:
            return "macOS vraagt toestemming om de beveiligde tunnel te starten."
        case .connecting:
            return "OpenConnect maakt de beveiligde tunnel gereed."
        case .connected:
            return "Je GlobalProtect-verbinding is beveiligd en actief."
        case .disconnecting:
            return "De tunnel wordt netjes afgesloten."
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
