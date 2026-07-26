import SwiftUI

/// Keeps card-based screens comfortable to scan on iPad while preserving the
/// edge-to-edge layout used on iPhone and in narrow Split View windows.
enum AdaptiveLayout {
    static let contentMaxWidth: CGFloat = 820
    static let quickCaptureMaxWidth: CGFloat = 720
}

private struct AdaptiveReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    func adaptiveReadableWidth(
        maxWidth: CGFloat = AdaptiveLayout.contentMaxWidth
    ) -> some View {
        modifier(AdaptiveReadableWidth(maxWidth: maxWidth))
    }
}
