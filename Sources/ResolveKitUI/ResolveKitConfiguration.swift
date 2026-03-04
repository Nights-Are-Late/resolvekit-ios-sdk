import Foundation
import ResolveKitCore

public enum ResolveKitDefaults {
    public static let baseURL = URL(string: "https://agent.resolvekit.app")!
    public static let sdkName = "resolvekit-ios-sdk"
    public static let sdkVersion = "0.1.0"
}

enum ResolveKitClientInfoProvider {
    static var osName: String {
        #if os(iOS)
        "iOS"
        #elseif os(macOS)
        "macOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(watchOS)
        "watchOS"
        #elseif os(visionOS)
        "visionOS"
        #else
        "unknown"
        #endif
    }

    static func makeClientPayload(
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> [String: String] {
        var payload: [String: String] = [
            "platform": ResolveKitPlatform.current.rawValue,
            "os_name": osName,
            "os_version": "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)",
            "app_version": infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "sdk_name": ResolveKitDefaults.sdkName,
            "sdk_version": ResolveKitDefaults.sdkVersion
        ]
        if let appBuild = infoDictionary?["CFBundleVersion"] as? String, !appBuild.isEmpty {
            payload["app_build"] = appBuild
        }
        return payload
    }
}

public struct ResolveKitConfiguration: Sendable {
    public let baseURL: URL
    public let apiKeyProvider: @Sendable () -> String?
    public let deviceIDProvider: @Sendable () -> String?
    public let llmContextProvider: @Sendable () -> JSONObject
    public let availableFunctionNamesProvider: (@Sendable () -> [String])?
    public let localeProvider: @Sendable () -> String?
    public let preferredLocalesProvider: (@Sendable () -> [String])?
    public let functions: [any AnyResolveKitFunction.Type]
    public let functionPacks: [any ResolveKitFunctionPack.Type]

    public init(
        baseURL: URL = ResolveKitDefaults.baseURL,
        apiKeyProvider: @escaping @Sendable () -> String?,
        deviceIDProvider: @escaping @Sendable () -> String? = { nil },
        llmContextProvider: @escaping @Sendable () -> JSONObject = { [:] },
        availableFunctionNamesProvider: (@Sendable () -> [String])? = nil,
        localeProvider: @escaping @Sendable () -> String? = { nil },
        preferredLocalesProvider: (@Sendable () -> [String])? = nil,
        functions: [any AnyResolveKitFunction.Type] = [],
        functionPacks: [any ResolveKitFunctionPack.Type] = []
    ) {
        self.baseURL = baseURL
        self.apiKeyProvider = apiKeyProvider
        self.deviceIDProvider = deviceIDProvider
        self.llmContextProvider = llmContextProvider
        self.availableFunctionNamesProvider = availableFunctionNamesProvider
        self.localeProvider = localeProvider
        self.preferredLocalesProvider = preferredLocalesProvider
        self.functions = functions
        self.functionPacks = functionPacks
    }

    public func resolvedPreferredLocales(preferredLanguages: @autoclosure () -> [String] = Locale.preferredLanguages) -> [String] {
        preferredLocalesProvider?() ?? preferredLanguages()
    }
}
