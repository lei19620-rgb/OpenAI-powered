import SwiftUI

enum AppTheme {
    /// Quiet, adaptive jade accent. Content stays primary; semantic warnings
    /// and system materials remain native in both appearances.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.84, blue: 0.72, alpha: 1)
            : UIColor(red: 0.04, green: 0.40, blue: 0.33, alpha: 1)
    })
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedBackground = Color(uiColor: .systemBackground)
    static let controlBackground = Color(uiColor: .tertiarySystemFill)
    static let separator = Color(uiColor: .separator)

    static let pagePadding: CGFloat = 20
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 22
    static let heroRadius: CGFloat = 28
}

extension View {
    func appCard(
        padding: CGFloat = AppTheme.cardPadding,
        radius: CGFloat = AppTheme.cardRadius
    ) -> some View {
        self
            .padding(padding)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: radius))
    }

    func appIconBadge(
        tint: Color = AppTheme.accent,
        size: CGFloat = 40,
        radius: CGFloat = 12
    ) -> some View {
        self
            .frame(width: size, height: size)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: radius))
    }
}
