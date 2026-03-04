import Foundation

enum ResolveKitLocaleResolver {
    private static let supportedCodes: Set<String> = [
        "ar", "bg", "bn", "bs", "ca", "cs", "da", "de", "el", "en", "en-gb", "es", "es-ar", "et", "fa", "fi",
        "fr", "hi", "he", "hr", "hu", "id", "it", "lv", "ms", "no", "ja", "ko", "nl", "pl", "pt", "pt-br", "ro",
        "ru", "sk", "sq", "sr", "sv", "sw", "th", "tr", "tl", "uk", "ur", "vi", "zh", "zh-tw", "zh-cn", "lt"
    ]

    private static let aliases: [String: String] = [
        "zh-hans": "zh-cn",
        "zh-hant": "zh-tw",
    ]

    static func resolve(locale: String?, preferredLocales: [String]) -> String {
        if let matched = match(locale) {
            return matched
        }
        for preferred in preferredLocales {
            if let matched = match(preferred) {
                return matched
            }
        }
        return "en"
    }

    static func match(_ locale: String?) -> String? {
        guard var code = normalize(locale) else { return nil }
        code = aliases[code] ?? code
        if supportedCodes.contains(code) {
            return code
        }
        let base = code.split(separator: "-", maxSplits: 1).first.map(String.init)
        if let base, supportedCodes.contains(base) {
            return base
        }
        return nil
    }

    static func normalize(_ locale: String?) -> String? {
        guard let locale else { return nil }
        let cleaned = locale.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return cleaned.isEmpty ? nil : cleaned
    }
}
