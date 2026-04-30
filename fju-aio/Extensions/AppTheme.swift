import SwiftUI

// MARK: - Unified App Design System

enum AppTheme {

    // MARK: - Color

    /// Single brand accent used throughout the app.
    static let accent = Color.accentColor

    // MARK: - Spacing & Shape

    static let cornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 16
}

// MARK: - View Modifiers

extension View {
    /// Standard card background
    func appCard(padding: CGFloat = AppTheme.cardPadding) -> some View {
        self
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}
