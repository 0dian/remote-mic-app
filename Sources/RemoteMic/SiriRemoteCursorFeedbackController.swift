import AppKit
import Foundation

struct SiriRemoteCursorFeedbackState: Equatable {
    enum Presentation: Equatable {
        case pointer(scale: CGFloat)
        case scroll(direction: VerticalDirection)
    }

    enum VerticalDirection: Equatable {
        case up
        case down
    }

    static func pointerScale(forSpeed speed: Double) -> CGFloat {
        let normalized = min(1, max(0, (speed - 2.0) / 70.0))
        let smooth = normalized * normalized * (3 - 2 * normalized)
        return 1.0 + CGFloat(smooth) * 1.2
    }

    static func scrollDirection(forPixels pixels: Double) -> VerticalDirection {
        pixels >= 0 ? .up : .down
    }

    static func scrollSymbolName(for direction: VerticalDirection) -> String {
        switch direction {
        case .up: "arrow.up.circle.fill"
        case .down: "arrow.down.circle.fill"
        }
    }
}

struct SiriRemoteCursorFeedbackLayout: Equatable {
    enum Placement: String, Equatable {
        case rightBelow = "right_below"
        case leftBelow = "left_below"
        case rightAbove = "right_above"
        case leftAbove = "left_above"
        case clamped
    }

    let frame: NSRect
    let placement: Placement

    static func layout(
        for point: NSPoint,
        visibleFrame: NSRect,
        size: CGFloat = 40,
        cursorBodySize: NSSize = NSSize(width: 18, height: 24),
        gap: CGFloat = 8
    ) -> SiriRemoteCursorFeedbackLayout {
        let belowY = point.y - size - 4
        let candidates: [(Placement, NSRect)] = [
            (.rightBelow, NSRect(
                x: point.x + cursorBodySize.width + gap,
                y: belowY,
                width: size,
                height: size
            )),
            (.leftBelow, NSRect(
                x: point.x - gap - size,
                y: belowY,
                width: size,
                height: size
            )),
            (.rightAbove, NSRect(
                x: point.x + cursorBodySize.width + gap,
                y: point.y + gap,
                width: size,
                height: size
            )),
            (.leftAbove, NSRect(
                x: point.x - gap - size,
                y: point.y + gap,
                width: size,
                height: size
            )),
        ]
        if let candidate = candidates.first(where: { visibleFrame.contains($0.1) }) {
            return SiriRemoteCursorFeedbackLayout(
                frame: candidate.1,
                placement: candidate.0
            )
        }
        let preferred = candidates[0].1
        return SiriRemoteCursorFeedbackLayout(
            frame: NSRect(
                x: min(max(preferred.minX, visibleFrame.minX), visibleFrame.maxX - size),
                y: min(max(preferred.minY, visibleFrame.minY), visibleFrame.maxY - size),
                width: size,
                height: size
            ),
            placement: .clamped
        )
    }

    static func cursorProtectionFrame(
        for point: NSPoint,
        cursorBodySize: NSSize = NSSize(width: 18, height: 24)
    ) -> NSRect {
        NSRect(
            x: point.x,
            y: point.y - cursorBodySize.height,
            width: cursorBodySize.width,
            height: cursorBodySize.height
        )
    }
}

final class SiriRemoteCursorFeedbackController {
    private let view = SiriRemoteCursorFeedbackView(
        frame: NSRect(x: 0, y: 0, width: 40, height: 40)
    )
    private let logger: (String) -> Void
    private var window: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var lastRenderUptime: TimeInterval = 0
    private var isFeedbackVisible = false

    init(logger: @escaping (String) -> Void = { _ in }) {
        self.logger = logger
    }

    func handle(_ feedback: SiriRemoteTouchFeedbackKind) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handle(feedback) }
            return
        }
        switch feedback {
        case let .pointerMoved(_, _, speed):
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastRenderUptime >= 1.0 / 120.0 else { return }
            lastRenderUptime = now
            view.presentation = .pointer(
                scale: SiriRemoteCursorFeedbackState.pointerScale(forSpeed: speed)
            )
            show(at: NSEvent.mouseLocation, mode: "pointer")
            scheduleHide(after: 0.24)
        case let .scrolled(pixels, _):
            view.presentation = .scroll(
                direction: SiriRemoteCursorFeedbackState.scrollDirection(forPixels: pixels)
            )
            show(at: NSEvent.mouseLocation, mode: "scroll")
            scheduleHide(after: 0.55)
        case .clicked:
            scheduleHide(after: 0.12)
        }
    }

    func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hide(reason: "app_stop")
    }

    private func show(at point: NSPoint, mode: String) {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = view
            window = panel
        }
        let visibleFrame = NSScreen.screens
            .first(where: { $0.visibleFrame.contains(point) })?
            .visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: point.x - 100, y: point.y - 100, width: 200, height: 200)
        let layout = SiriRemoteCursorFeedbackLayout.layout(
            for: point,
            visibleFrame: visibleFrame
        )
        window?.setFrame(layout.frame, display: true)
        window?.orderFrontRegardless()
        view.needsDisplay = true
        if !isFeedbackVisible {
            isFeedbackVisible = true
            logger(
                "APPLE REMOTE TOUCH FEEDBACK phase=shown result=visible " +
                    "mode=\(mode) placement=\(layout.placement.rawValue)"
            )
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide(reason: "idle_timeout")
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func hide(reason: String) {
        window?.orderOut(nil)
        guard isFeedbackVisible else { return }
        isFeedbackVisible = false
        logger(
            "APPLE REMOTE TOUCH FEEDBACK phase=hidden result=completed reason=\(reason)"
        )
    }
}

private final class SiriRemoteCursorFeedbackView: NSView {
    var presentation: SiriRemoteCursorFeedbackState.Presentation = .pointer(scale: 1.0)

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch presentation {
        case let .pointer(scale):
            drawPointer(scale: scale)
        case let .scroll(direction):
            drawScroll(direction: direction)
        }
    }

    private func drawPointer(scale: CGFloat) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = 7.0 * scale
        let halo = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        halo.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        halo.lineWidth = 2
        halo.stroke()

        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: center.x - 2.5,
            y: center.y - 2.5,
            width: 5,
            height: 5
        )).fill()
    }

    private func drawScroll(direction: SiriRemoteCursorFeedbackState.VerticalDirection) {
        let symbolName = SiriRemoteCursorFeedbackState.scrollSymbolName(for: direction)
        guard let baseImage = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        ) else { return }
        let pointSize = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let palette = NSImage.SymbolConfiguration(paletteColors: [
            NSColor.controlAccentColor.withAlphaComponent(0.96),
            NSColor.white.withAlphaComponent(0.98),
        ])
        let image = baseImage.withSymbolConfiguration(pointSize.applying(palette)) ?? baseImage
        image.draw(
            in: NSRect(x: bounds.midX - 11, y: bounds.midY - 11, width: 22, height: 22),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }
}
