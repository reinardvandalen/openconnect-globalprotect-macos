import Foundation

public enum VPNEndpointError: LocalizedError, Equatable {
    case empty
    case invalid
    case insecureScheme
    case credentialsInURL

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Vul het adres van je GlobalProtect-portal in."
        case .invalid:
            return "Dit is geen geldig GlobalProtect-adres."
        case .insecureScheme:
            return "Gebruik een beveiligd https-adres."
        case .credentialsInURL:
            return "Zet geen gebruikersnaam of wachtwoord in het VPN-adres."
        }
    }
}

public enum VPNEndpoint {
    public static func normalize(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VPNEndpointError.empty
        }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else {
            candidate = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            throw VPNEndpointError.invalid
        }

        guard scheme == "https" else {
            throw VPNEndpointError.insecureScheme
        }

        guard components.user == nil, components.password == nil else {
            throw VPNEndpointError.credentialsInURL
        }

        components.scheme = "https"
        components.fragment = nil

        guard let url = components.url else {
            throw VPNEndpointError.invalid
        }
        return url
    }
}
