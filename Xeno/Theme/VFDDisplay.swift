import SwiftUI
import UIKit

/// Turns the entire screen into a VFD pixel matrix while the Amber VFD theme is on.
///
/// Every app window (screens, nav and tab bars, lists, controls, sheets) is rasterized at one
/// pixel per VFD cell and enlarged with nearest-neighbour filtering, so everything is drawn with
/// the same square pixels. A pass-through window on top draws the dark gaps between pixels,
/// aligned to the same grid, plus the tube vignette.
final class VFDDisplay: NSObject {
    static let shared = VFDDisplay()
    private var gridWindow: UIWindow?
    private var link: CADisplayLink?
    private var active = false

    func apply(_ on: Bool) {
        active = on
        if on, link == nil {
            // Keep every layer point-sampled while the theme is on: each VFD cell takes the colour
            // at its centre instead of an average, so pixel-font text stays crisp (on or off).
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 20)
            l.add(to: .main, forMode: .common)
            link = l
        } else if !on {
            link?.invalidate(); link = nil
        }
        walkAll(nearest: on)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window !== gridWindow {
                let layer = window.layer
                layer.shouldRasterize = on
                layer.rasterizationScale = on ? 1 / Theme.vfdPixel : window.screen.scale
                layer.magnificationFilter = on ? .nearest : .linear
            }
            if on {
                if gridWindow == nil {
                    let w = UIWindow(windowScene: scene)
                    w.windowLevel = .alert + 10
                    w.isUserInteractionEnabled = false
                    w.backgroundColor = .clear
                    let vc = UIViewController()
                    vc.view = VFDGridView()
                    w.rootViewController = vc
                    gridWindow = w
                }
                gridWindow?.isHidden = false
                gridWindow?.rootViewController?.view.setNeedsDisplay()
            } else {
                gridWindow?.isHidden = true
                gridWindow = nil
            }
        }
    }
}

extension VFDDisplay {
    @objc private func tick() { if active { walkAll(nearest: true) } }

    private func walkAll(nearest: Bool) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window !== gridWindow { walk(window.layer, nearest) }
        }
    }

    private func walk(_ layer: CALayer, _ nearest: Bool) {
        let filter: CALayerContentsFilter = nearest ? .nearest : .linear
        if layer.minificationFilter != filter { layer.minificationFilter = filter }
        if layer.magnificationFilter != filter { layer.magnificationFilter = filter }
        layer.sublayers?.forEach { walk($0, nearest) }
    }
}

/// Draws the dark lines between VFD pixels (one device pixel wide) and a vignette.
final class VFDGridView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let pitch = Theme.vfdPixel
        let gap = 1 / max(window?.screen.scale ?? 3, 1)   // one device pixel
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.9).cgColor)
        var x: CGFloat = pitch - gap
        while x < bounds.width { ctx.fill(CGRect(x: x, y: 0, width: gap, height: bounds.height)); x += pitch }
        var y: CGFloat = pitch - gap
        while y < bounds.height { ctx.fill(CGRect(x: 0, y: y, width: bounds.width, height: gap)); y += pitch }
        // Tube vignette.
        let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.45).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            let c = CGPoint(x: bounds.midX, y: bounds.midY)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: bounds.width * 0.55, endCenter: c,
                                   endRadius: max(bounds.width, bounds.height) * 0.75, options: [.drawsAfterEndLocation])
        }
    }
}
