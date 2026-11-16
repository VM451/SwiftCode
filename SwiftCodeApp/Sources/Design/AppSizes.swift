import CoreGraphics

/// Single canonical component size scale for `SwiftCodeApp`.
enum AppSizes {
    // Heights
    static let heightCompact: CGFloat = 32
    static let heightStandard: CGFloat = 44
    static let heightLarge: CGFloat = 56
    static let heightInspectorPanel: CGFloat = 220

    // Icons
    static let iconSmall: CGFloat = 16
    static let iconMedium: CGFloat = 20
    static let iconLarge: CGFloat = 28

    // Images
    static let imageSmall: CGFloat = 40
    static let imageMedium: CGFloat = 64
    static let imageLarge: CGFloat = 96

    // Fixed widths (only when flexing cannot work)
    static let widthCompact: CGFloat = 120
    static let widthSidebarMin: CGFloat = 210
    static let widthStandard: CGFloat = 240
    static let widthLarge: CGFloat = 340
    static let widthContentMin: CGFloat = 380
    static let widthContentIdeal: CGFloat = 480
    static let widthWindowMin: CGFloat = 1120
    static let heightWindowMin: CGFloat = 700

    // Corner radii
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
}
