import SwiftUI

enum Theme {
    static let background    = Color(hex: "#0D0F10")
    static let surface       = Color(hex: "#1C1E21")
    static let accent        = Color(hex: "#FC4C02")  // Strava orange
    static let userBubble    = Color(hex: "#1A2744")
    static let textPrimary   = Color(hex: "#F5F5F5")
    static let textSecondary = Color(hex: "#8A8A8A")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
