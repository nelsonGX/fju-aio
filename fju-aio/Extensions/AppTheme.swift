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

    static let readableContentMaxWidth: CGFloat = 980
    static let compactHorizontalPadding: CGFloat = 16
    static let regularHorizontalPadding: CGFloat = 24
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

    /// Keeps phone-first screens from stretching awkwardly across iPad portrait or landscape.
    func readableContent(maxWidth: CGFloat = AppTheme.readableContentMaxWidth) -> some View {
        modifier(ReadableContentModifier(maxWidth: maxWidth))
    }

    func adaptiveListContentMargins(maxWidth: CGFloat = AppTheme.readableContentMaxWidth) -> some View {
        modifier(AdaptiveListContentMarginsModifier(maxWidth: maxWidth))
    }
}

private struct ReadableContentModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: maxWidth, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, AppTheme.regularHorizontalPadding)
        } else {
            content
                .padding(.horizontal, AppTheme.compactHorizontalPadding)
        }
    }
}

private struct AdaptiveListContentMarginsModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            GeometryReader { proxy in
                let margin = max(0, (proxy.size.width - maxWidth) / 2)
                content
                    .contentMargins(.horizontal, margin, for: .scrollContent)
            }
        } else {
            content
        }
    }
}
