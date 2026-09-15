import SwiftUI

// Ported from the Android build's values/colors.xml (neon red on black).
enum Theme {
    static let black      = Color(hex: 0x000000)
    static let darkGrey   = Color(hex: 0x141414)
    static let cardGrey   = Color(hex: 0x1B1B1B)
    static let neonRed    = Color(hex: 0xFF003C)
    static let neonRedDim = Color(hex: 0xB3002A)
    static let redGlow    = Color(hex: 0x4A0000)
    static let textHint   = Color(hex: 0x5C5C5C)
    static let text       = Color.white
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
