import SwiftUI

/// Corner concentricity (HIG, iOS 26): a shape nested in a container keeps the container's
/// curve, its radius being the container's minus the gap between them — never less than the
/// token's. Containers declare their corner with `sharpitContainerCorner`; what sits inside fills
/// with `sharpitConcentricBackground`. Before iOS 26 both fall back to the token's fixed corner.
extension View {
    /// Declares this view's rounded corner, so concentric shapes inside follow it.
    func sharpitContainerCorner(_ radius: CGFloat) -> some View {
        modifier(SharpitContainerCorner(radius: radius))
    }

    /// Fills behind this view with a corner concentric to its container, `minimum` at least.
    func sharpitConcentricBackground<S: ShapeStyle>(_ style: S, minimum radius: CGFloat) -> some View {
        modifier(SharpitConcentricBackground(style: style, radius: radius))
    }

    /// Clips this view to a corner concentric to its container, `minimum` at least.
    func sharpitConcentricClip(minimum radius: CGFloat) -> some View {
        modifier(SharpitConcentricClip(radius: radius))
    }
}

private struct SharpitContainerCorner: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // The iOS 26 overload is the one concentric shapes resolve against.
            let shape: some RoundedRectangularShape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content.containerShape(shape)
        } else {
            content
        }
    }
}

private struct SharpitConcentricBackground<S: ShapeStyle>: ViewModifier {
    let style: S
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.background(style, in: ConcentricRectangle(corners: .concentric(minimum: .fixed(radius)), isUniform: true))
        } else {
            content.background(style, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

private struct SharpitConcentricClip: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(radius)), isUniform: true)
            content.clipShape(shape).contentShape(shape)
        } else {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content.clipShape(shape).contentShape(shape)
        }
    }
}
