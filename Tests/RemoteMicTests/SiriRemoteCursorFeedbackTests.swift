import CoreGraphics
import Foundation
import Testing
@testable import RemoteMic

@Suite("Siri Remote cursor feedback")
struct SiriRemoteCursorFeedbackTests {
    @Test func pointerScaleIsBoundedAndGrowsWithSpeed() {
        let slow = SiriRemoteCursorFeedbackState.pointerScale(forSpeed: 0)
        let medium = SiriRemoteCursorFeedbackState.pointerScale(forSpeed: 30)
        let fast = SiriRemoteCursorFeedbackState.pointerScale(forSpeed: 500)

        #expect(slow == 1.0)
        #expect(slow < medium)
        #expect(medium < fast)
        #expect(abs(Double(fast) - 2.2) < 0.0001)
    }

    @Test func scrollFeedbackUsesDirectionOnly() {
        #expect(SiriRemoteCursorFeedbackState.scrollDirection(forPixels: 4) == .up)
        #expect(SiriRemoteCursorFeedbackState.scrollDirection(forPixels: -4) == .down)
        #expect(SiriRemoteCursorFeedbackState.scrollSymbolName(for: .up) == "arrow.up.circle.fill")
        #expect(SiriRemoteCursorFeedbackState.scrollSymbolName(for: .down) == "arrow.down.circle.fill")
    }

    @Test func preferredFeedbackFrameIsRightBelowAndNeverOverlapsTheCursorBody() {
        let point = CGPoint(x: 400, y: 300)
        let layout = SiriRemoteCursorFeedbackLayout.layout(
            for: point,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )
        let cursorBody = SiriRemoteCursorFeedbackLayout.cursorProtectionFrame(for: point)

        #expect(layout.placement == .rightBelow)
        #expect(layout.frame.minX > cursorBody.maxX)
        #expect(!layout.frame.intersects(cursorBody))
        #expect(!layout.frame.contains(point))
    }

    @Test func feedbackFlipsAwayFromScreenEdgesWithoutCoveringTheCursor() {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        for point in [
            CGPoint(x: 998, y: 2),
            CGPoint(x: 998, y: 798),
            CGPoint(x: 2, y: 2),
        ] {
            let layout = SiriRemoteCursorFeedbackLayout.layout(
                for: point,
                visibleFrame: screen
            )
            let cursorBody = SiriRemoteCursorFeedbackLayout.cursorProtectionFrame(for: point)
            #expect(screen.contains(layout.frame))
            #expect(!layout.frame.intersects(cursorBody))
        }
    }

    @Test func hostWiresPrivateTouchFeedbackIntoTheVisibleController() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let integration = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/RemoteMic/SiriRemoteFeatureIntegration.swift"
            ),
            encoding: .utf8
        )
        let model = try String(
            contentsOf: root.appendingPathComponent("Sources/RemoteMic/BridgeAppModel.swift"),
            encoding: .utf8
        )

        #expect(integration.contains("feature.onTouchFeedback ="))
        #expect(model.contains("siriRemoteFeature.onTouchFeedback ="))
        #expect(model.contains("siriRemoteCursorFeedback.handle(feedback)"))
        #expect(model.contains("siriRemoteCursorFeedback.stop()"))
    }
}
