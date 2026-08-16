import Foundation

public enum AuthenticationPrompt: Equatable, Sendable {
    case gateway(String)
    case password
    case verification
}

public struct AuthenticationPromptDetector: Sendable {
    private struct Marker: Sendable {
        let text: String
        let prompt: AuthenticationPrompt
    }

    private static let markers = [
        Marker(text: "verification code:", prompt: .verification),
        Marker(text: "verificatiecode:", prompt: .verification),
        Marker(text: "one-time password:", prompt: .verification),
        Marker(text: "one time password:", prompt: .verification),
        Marker(text: "mfa code:", prompt: .verification),
        Marker(text: "passcode:", prompt: .verification),
        Marker(text: "challenge:", prompt: .verification),
        Marker(text: "uitdaging:", prompt: .verification),
        Marker(text: "response:", prompt: .verification),
        Marker(text: "antwoord:", prompt: .verification),
        Marker(text: "token:", prompt: .verification),
        Marker(text: "otp:", prompt: .verification),
        Marker(text: "password:", prompt: .password),
        Marker(text: "wachtwoord:", prompt: .password)
    ]

    private var text = ""
    private var lastMatchEnd = 0

    public init() {}

    public mutating func append(_ newText: String) -> [AuthenticationPrompt] {
        text.append(newText)

        let lowercaseText = text.lowercased() as NSString
        var matches: [(range: NSRange, prompt: AuthenticationPrompt)] = []
        matches.append(contentsOf: gatewayMatches(in: text as NSString))

        for marker in Self.markers {
            var searchRange = NSRange(location: 0, length: lowercaseText.length)

            while searchRange.length > 0 {
                let match = lowercaseText.range(of: marker.text, options: [], range: searchRange)
                guard match.location != NSNotFound else { break }
                matches.append((match, marker.prompt))

                let nextLocation = NSMaxRange(match)
                searchRange = NSRange(
                    location: nextLocation,
                    length: lowercaseText.length - nextLocation
                )
            }
        }

        var prompts: [AuthenticationPrompt] = []
        for match in matches.sorted(by: {
            let firstEnd = NSMaxRange($0.range)
            let secondEnd = NSMaxRange($1.range)
            if firstEnd == secondEnd {
                return Self.priority(of: $0.prompt) > Self.priority(of: $1.prompt)
            }
            return firstEnd < secondEnd
        }) {
            let matchEnd = NSMaxRange(match.range)
            guard matchEnd > lastMatchEnd else { continue }
            lastMatchEnd = matchEnd
            prompts.append(match.prompt)
        }

        return prompts
    }

    private func gatewayMatches(
        in sourceText: NSString
    ) -> [(range: NSRange, prompt: AuthenticationPrompt)] {
        guard let expression = try? NSRegularExpression(
            pattern: #"gateway:\s*\[([^\]|]+)\]:"#,
            options: [.caseInsensitive]
        ) else { return [] }

        return expression.matches(
            in: sourceText as String,
            range: NSRange(location: 0, length: sourceText.length)
        ).compactMap { match in
            guard match.numberOfRanges == 2 else { return nil }
            let gatewayRange = match.range(at: 1)
            guard gatewayRange.location != NSNotFound else { return nil }
            let gateway = sourceText.substring(with: gatewayRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !gateway.isEmpty else { return nil }
            return (match.range, .gateway(gateway))
        }
    }

    private static func priority(of prompt: AuthenticationPrompt) -> Int {
        switch prompt {
        case .verification:
            return 3
        case .gateway:
            return 2
        case .password:
            return 1
        }
    }
}
