import Foundation

public enum ResolveKitAppearanceMode: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case light
    case dark
}

public struct ResolveKitChatPalette: Codable, Sendable, Equatable {
    public let screenBackground: String
    public let titleText: String
    public let statusText: String
    public let composerBackground: String
    public let composerText: String
    public let composerPlaceholder: String
    public let userBubbleBackground: String
    public let userBubbleText: String
    public let assistantBubbleBackground: String
    public let assistantBubbleText: String
    public let loaderBubbleBackground: String
    public let loaderDotActive: String
    public let loaderDotInactive: String
    public let toolCardBackground: String
    public let toolCardBorder: String
    public let toolCardTitle: String
    public let toolCardBody: String

    public init(
        screenBackground: String,
        titleText: String,
        statusText: String,
        composerBackground: String,
        composerText: String,
        composerPlaceholder: String,
        userBubbleBackground: String,
        userBubbleText: String,
        assistantBubbleBackground: String,
        assistantBubbleText: String,
        loaderBubbleBackground: String,
        loaderDotActive: String,
        loaderDotInactive: String,
        toolCardBackground: String,
        toolCardBorder: String,
        toolCardTitle: String,
        toolCardBody: String
    ) {
        self.screenBackground = screenBackground
        self.titleText = titleText
        self.statusText = statusText
        self.composerBackground = composerBackground
        self.composerText = composerText
        self.composerPlaceholder = composerPlaceholder
        self.userBubbleBackground = userBubbleBackground
        self.userBubbleText = userBubbleText
        self.assistantBubbleBackground = assistantBubbleBackground
        self.assistantBubbleText = assistantBubbleText
        self.loaderBubbleBackground = loaderBubbleBackground
        self.loaderDotActive = loaderDotActive
        self.loaderDotInactive = loaderDotInactive
        self.toolCardBackground = toolCardBackground
        self.toolCardBorder = toolCardBorder
        self.toolCardTitle = toolCardTitle
        self.toolCardBody = toolCardBody
    }
}

public struct ResolveKitChatTheme: Codable, Sendable, Equatable {
    public let light: ResolveKitChatPalette
    public let dark: ResolveKitChatPalette

    public init(light: ResolveKitChatPalette, dark: ResolveKitChatPalette) {
        self.light = light
        self.dark = dark
    }

    public static let `default` = ResolveKitChatTheme(
        light: ResolveKitChatPalette(
            screenBackground: "#F7F7FA",
            titleText: "#111827",
            statusText: "#4B5563",
            composerBackground: "#FFFFFF",
            composerText: "#111827",
            composerPlaceholder: "#9CA3AF",
            userBubbleBackground: "#DBEAFE",
            userBubbleText: "#1E3A8A",
            assistantBubbleBackground: "#E5E7EB",
            assistantBubbleText: "#111827",
            loaderBubbleBackground: "#E5E7EB",
            loaderDotActive: "#374151",
            loaderDotInactive: "#9CA3AF",
            toolCardBackground: "#FFFFFFCC",
            toolCardBorder: "#D1D5DB",
            toolCardTitle: "#111827",
            toolCardBody: "#374151"
        ),
        dark: ResolveKitChatPalette(
            screenBackground: "#0B0C10",
            titleText: "#E5E7EB",
            statusText: "#9CA3AF",
            composerBackground: "#111318",
            composerText: "#E5E7EB",
            composerPlaceholder: "#6B7280",
            userBubbleBackground: "#1E3A8A99",
            userBubbleText: "#DBEAFE",
            assistantBubbleBackground: "#1F2937",
            assistantBubbleText: "#E5E7EB",
            loaderBubbleBackground: "#1F2937",
            loaderDotActive: "#E5E7EB",
            loaderDotInactive: "#6B7280",
            toolCardBackground: "#111318CC",
            toolCardBorder: "#374151",
            toolCardTitle: "#E5E7EB",
            toolCardBody: "#9CA3AF"
        )
    )
}
