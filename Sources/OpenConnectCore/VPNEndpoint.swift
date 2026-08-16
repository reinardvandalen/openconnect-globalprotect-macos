import Foundation

public enum VPNEndpointError: LocalizedError, Equatable {
    case empty
    case invalid
    case insecureScheme
    case credentialsInURL

    public var errorDescription: String? {
        switch self {
        case .empty:
            return L10n.text("error.endpoint_empty")
        case .invalid:
            return L10n.text("error.endpoint_invalid")
        case .insecureScheme:
            return L10n.text("error.endpoint_insecure")
        case .credentialsInURL:
            return L10n.text("error.endpoint_credentials")
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
