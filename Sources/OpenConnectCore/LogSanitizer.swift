import Foundation

public enum LogSanitizer {
    public static func sanitize(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                let uppercased = line.uppercased()
                return !uppercased.hasPrefix("COOKIE=") &&
                    !uppercased.contains("AUTHCOOKIE=") &&
                    !uppercased.contains("PORTAL-USERAUTHCOOKIE=")
            }
            .joined(separator: "\n")
    }
}
