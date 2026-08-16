import Foundation

public enum AuthenticationResultError: LocalizedError, Equatable {
    case missingCookie
    case missingServer

    public var errorDescription: String? {
        switch self {
        case .missingCookie:
            return "OpenConnect heeft na het inloggen geen VPN-cookie teruggegeven."
        case .missingServer:
            return "OpenConnect heeft na het inloggen geen VPN-server teruggegeven."
        }
    }
}

public struct AuthenticationResult: Equatable, Sendable {
    public let cookie: String
    public let connectURL: String
    public let fingerprint: String?
    public let resolve: String?

    public init(cookie: String, connectURL: String, fingerprint: String?, resolve: String?) {
        self.cookie = cookie
        self.connectURL = connectURL
        self.fingerprint = fingerprint
        self.resolve = resolve
    }

    public static func parse(_ output: String) throws -> AuthenticationResult {
        var values: [String: String] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let separator = line.firstIndex(of: "=") else { continue }

            let key = String(line[..<separator])
            guard ["COOKIE", "CONNECT_URL", "HOST", "FINGERPRINT", "RESOLVE"].contains(key) else {
                continue
            }

            let rawValue = String(line[line.index(after: separator)...])
            values[key] = unquoteShellValue(rawValue)
        }

        guard let cookie = values["COOKIE"], !cookie.isEmpty else {
            throw AuthenticationResultError.missingCookie
        }

        guard let server = values["CONNECT_URL"] ?? values["HOST"], !server.isEmpty else {
            throw AuthenticationResultError.missingServer
        }

        return AuthenticationResult(
            cookie: cookie,
            connectURL: server,
            fingerprint: nonEmpty(values["FINGERPRINT"]),
            resolve: nonEmpty(values["RESOLVE"])
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func unquoteShellValue(_ rawValue: String) -> String {
        guard rawValue.count >= 2 else { return rawValue }

        if rawValue.hasPrefix("'") && rawValue.hasSuffix("'") {
            let inner = rawValue.dropFirst().dropLast()
            return inner.replacingOccurrences(of: "'\\''", with: "'")
        }

        if rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"") {
            let inner = rawValue.dropFirst().dropLast()
            return inner
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }

        return rawValue
    }
}
