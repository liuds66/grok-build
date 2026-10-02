import AppKit

/// Scroll documents use a top-left origin so AppKit scrolling and stack-view
/// layout share one coordinate system.
final class FlippedLayerView: LayerView {
    override var isFlipped: Bool { true }
}
