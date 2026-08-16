import Foundation

public enum L10n {
    public static let supportedLanguages = ["en", "nl", "de"]

    private static let resourceBundleName = "OpenConnectVPN_OpenConnectCore.bundle"

    public static func text(_ key: String, language: String? = nil) -> String {
        bundle(for: language).localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let format = text(key)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static func bundle(for requestedLanguage: String?) -> Bundle {
        let resources = resourceBundle
        let language = requestedLanguage ?? ProcessInfo.processInfo.environment["OPENCONNECT_LANGUAGE"]

        guard let language,
              supportedLanguages.contains(language),
              let path = resources.path(forResource: language, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return resources
        }

        return localizedBundle
    }

    private static var resourceBundle: Bundle {
        if let resourcesURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourcesURL.appendingPathComponent(resourceBundleName, isDirectory: true)
           ) {
            return packagedBundle
        }

        return .module
    }
}
