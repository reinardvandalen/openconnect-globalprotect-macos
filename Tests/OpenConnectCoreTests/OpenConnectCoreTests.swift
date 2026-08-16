import Foundation
import XCTest
@testable import OpenConnectCore

final class OpenConnectCoreTests: XCTestCase {
    func testInterfaceTranslationsAreAvailable() {
        XCTAssertEqual(L10n.supportedLanguages, ["en", "nl", "de"])
        XCTAssertEqual(L10n.text("phase.inactive.title", language: "en"), "Not connected")
        XCTAssertEqual(L10n.text("phase.inactive.title", language: "nl"), "Niet verbonden")
        XCTAssertEqual(L10n.text("phase.inactive.title", language: "de"), "Nicht verbunden")

        let representativeKeys = [
            "app.subtitle",
            "field.username.label",
            "toggle.remember.title",
            "button.connect",
            "error.endpoint_invalid",
            "error.authentication_failed"
        ]

        for language in L10n.supportedLanguages {
            for key in representativeKeys {
                XCTAssertNotEqual(
                    L10n.text(key, language: language),
                    key,
                    "Missing \(language) translation for \(key)"
                )
            }
        }
    }

    func testNormalizesHostnameToHTTPS() throws {
        let url = try VPNEndpoint.normalize("vpn.example.nl")
        XCTAssertEqual(url.absoluteString, "https://vpn.example.nl")
    }

    func testKeepsPortAndGatewayPath() throws {
        let url = try VPNEndpoint.normalize("https://vpn.example.nl:4443/gateway")
        XCTAssertEqual(url.absoluteString, "https://vpn.example.nl:4443/gateway")
    }

    func testRejectsHTTPAndCredentials() {
        XCTAssertThrowsError(try VPNEndpoint.normalize("http://vpn.example.nl")) { error in
            XCTAssertEqual(error as? VPNEndpointError, .insecureScheme)
        }
        XCTAssertThrowsError(try VPNEndpoint.normalize("https://user:secret@vpn.example.nl")) { error in
            XCTAssertEqual(error as? VPNEndpointError, .credentialsInURL)
        }
    }

    func testParsesAuthenticationOutput() throws {
        let output = """
        COOKIE='cookie-value'
        HOST='192.0.2.10'
        CONNECT_URL='https://vpn.example.nl/gateway'
        FINGERPRINT='sha256:abcdef'
        RESOLVE='vpn.example.nl:192.0.2.10'
        """

        let result = try AuthenticationResult.parse(output)
        XCTAssertEqual(result.cookie, "cookie-value")
        XCTAssertEqual(result.connectURL, "https://vpn.example.nl/gateway")
        XCTAssertEqual(result.fingerprint, "sha256:abcdef")
        XCTAssertEqual(result.resolve, "vpn.example.nl:192.0.2.10")
    }

    func testFallsBackToHost() throws {
        let result = try AuthenticationResult.parse("COOKIE='abc'\nHOST='192.0.2.10'\n")
        XCTAssertEqual(result.connectURL, "192.0.2.10")
    }

    func testShellQuoting() {
        XCTAssertEqual(ShellEscaping.quote("it's safe"), "'it'\"'\"'s safe'")
    }

    func testTunnelStopCommandHasValidShellSyntax() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-n",
            "-c",
            TunnelStopCommand.make(pidFilePath: "/tmp/OpenConnect VPN/openconnect.pid")
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testTunnelStopCommandNeverForcesTermination() {
        let command = TunnelStopCommand.make(pidFilePath: "/tmp/openconnect.pid")

        XCTAssertTrue(command.contains("/bin/kill -TERM"))
        XCTAssertFalse(command.contains("/bin/kill -KILL"))
    }

    func testKeychainPasswordStoreLifecycle() throws {
        let store = KeychainPasswordStore(
            service: "nl.eikeldal.OpenConnectVPN.tests.\(UUID().uuidString)",
            account: "test-password"
        )
        defer { try? store.delete() }

        XCTAssertNil(try store.load())

        try store.save("eerste-geheim")
        XCTAssertEqual(try store.load(), "eerste-geheim")

        try store.save("bijgewerkt-geheim")
        XCTAssertEqual(try store.load(), "bijgewerkt-geheim")

        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testSanitizerRemovesCookies() {
        let input = "Starting\nCOOKIE='secret'\nConnected"
        XCTAssertEqual(LogSanitizer.sanitize(input), "Starting\nConnected")
    }

    func testDetectsAuthenticationPromptAcrossOutputChunks() {
        var detector = AuthenticationPromptDetector()

        XCTAssertEqual(detector.append("Enter login credentials Pass"), [])
        XCTAssertEqual(detector.append("word: "), [.password])
        XCTAssertEqual(detector.append(""), [])
    }

    func testDetectsASecondAuthenticationPrompt() {
        var detector = AuthenticationPromptDetector()

        XCTAssertEqual(detector.append("Password: "), [.password])
        XCTAssertEqual(detector.append("Enter verification code: "), [.verification])
    }

    func testDetectsLocalizedMFAChallenge() {
        var detector = AuthenticationPromptDetector()

        XCTAssertEqual(
            detector.append("Please enter the Google Authenticator Token Code\nUitdaging: "),
            [.verification]
        )
    }

    func testDetectsGermanAuthenticationPrompts() {
        var detector = AuthenticationPromptDetector()

        XCTAssertEqual(detector.append("Passwort: "), [.password])
        XCTAssertEqual(detector.append("Verifizierungscode: "), [.verification])
    }

    func testDetectsSingleGatewaySelection() {
        var detector = AuthenticationPromptDetector()

        XCTAssertEqual(
            detector.append("Selecteer een GlobalProtect-gateway.\nGATEWAY: [Example Gateway]:"),
            [.gateway("Example Gateway")]
        )
    }
}
