import SwiftUI
import ResolveKitCore

extension Color {
    init(resolveKitHex: String) {
        let hex = resolveKitHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(raw, radix: 16) ?? 0

        switch raw.count {
        case 6:
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b)
        case 8:
            let r = Double((value >> 24) & 0xFF) / 255.0
            let g = Double((value >> 16) & 0xFF) / 255.0
            let b = Double((value >> 8) & 0xFF) / 255.0
            let a = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, opacity: a)
        default:
            self = .clear
        }
    }
}

extension ResolveKitChatPalette {
    var screenBackgroundColor: Color { Color(resolveKitHex: screenBackground) }
    var titleTextColor: Color { Color(resolveKitHex: titleText) }
    var statusTextColor: Color { Color(resolveKitHex: statusText) }
    var composerBackgroundColor: Color { Color(resolveKitHex: composerBackground) }
    var composerTextColor: Color { Color(resolveKitHex: composerText) }
    var composerPlaceholderColor: Color { Color(resolveKitHex: composerPlaceholder) }
    var userBubbleBackgroundColor: Color { Color(resolveKitHex: userBubbleBackground) }
    var userBubbleTextColor: Color { Color(resolveKitHex: userBubbleText) }
    var assistantBubbleBackgroundColor: Color { Color(resolveKitHex: assistantBubbleBackground) }
    var assistantBubbleTextColor: Color { Color(resolveKitHex: assistantBubbleText) }
    var loaderBubbleBackgroundColor: Color { Color(resolveKitHex: loaderBubbleBackground) }
    var loaderDotActiveColor: Color { Color(resolveKitHex: loaderDotActive) }
    var loaderDotInactiveColor: Color { Color(resolveKitHex: loaderDotInactive) }
    var toolCardBackgroundColor: Color { Color(resolveKitHex: toolCardBackground) }
    var toolCardBorderColor: Color { Color(resolveKitHex: toolCardBorder) }
    var toolCardTitleColor: Color { Color(resolveKitHex: toolCardTitle) }
    var toolCardBodyColor: Color { Color(resolveKitHex: toolCardBody) }
}
