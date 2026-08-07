import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Keeps card-based screens comfortable to scan on iPad while preserving the
/// edge-to-edge layout used on iPhone and in narrow Split View windows.
enum AdaptiveLayout {
    /// A generous reading column on iPad. It remains narrow enough for rows
    /// and tutorials to be scanned comfortably, while no longer making the
    /// interface feel like an iPhone-sized card in the middle of the screen.
    static let contentMaxWidth: CGFloat = 880
    static let quickCaptureMaxWidth: CGFloat = 720
    static var isPad: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    static func scaled(_ value: CGFloat) -> CGFloat {
        isPad ? value * 1.5 : value
    }
}

private struct AdaptiveReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                // A guaranteed gutter keeps cards and controls away from the
                // screen edges on iPads whose width is close to `maxWidth`,
                // where the centered column alone would leave almost none.
                .padding(.horizontal, AdaptiveLayout.isPad ? 24 : 0)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

/// Gives iPad a deliberately roomier baseline without scaling a whole view
/// tree. Scaling the tree would also scale its coordinate space and can make
/// tutorial highlights, popovers and keyboard avoidance drift. Environment
/// values preserve those positions while making native controls and text more
/// comfortable to use.
private struct IPadComfortableControls: ViewModifier {
    // Raising the Dynamic Type floor makes text styles (.body, .headline, …)
    // and native controls track the ×1.5 scaling of the fixed-size fonts,
    // while still honouring a user's even larger Dynamic Type choice.
    // Sheets use `.xLarge`: forms full of secondary text feel bloated at the
    // main content's `.xxLarge`.
    var textFloor: DynamicTypeSize = .xxLarge

    func body(content: Content) -> some View {
        if AdaptiveLayout.isPad {
            content
                .controlSize(.large)
                .dynamicTypeSize(textFloor...)
                .environment(\.defaultMinListRowHeight, 60)
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

    func iPadComfortableControls(
        textFloor: DynamicTypeSize = .xxLarge
    ) -> some View {
        modifier(IPadComfortableControls(textFloor: textFloor))
    }
}
