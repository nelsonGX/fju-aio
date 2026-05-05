import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Blends this color with another color by a given amount.
    /// Provides backward compatibility for iOS versions older than 18.0.
    func mixed(with other: Color, by amount: Double) -> Color {
        if #available(iOS 18.0, *) {
            return self.mix(with: other, by: amount)
        } else {
            #if canImport(UIKit)
            let uiColor1 = UIColor(self)
            let uiColor2 = UIColor(other)
            
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            
            guard uiColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
                  uiColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
                return self
            }
            
            return Color(
                red: Double(r1 + (r2 - r1) * CGFloat(amount)),
                green: Double(g1 + (g2 - g1) * CGFloat(amount)),
                blue: Double(b1 + (b2 - b1) * CGFloat(amount)),
                opacity: Double(a1 + (a2 - a1) * CGFloat(amount))
            )
            #else
            return self
            #endif
        }
    }
}
