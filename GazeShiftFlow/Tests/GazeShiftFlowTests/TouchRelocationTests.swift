import Foundation
import Testing
import GazeShiftCore
@testable import GazeShiftFlow

@Suite("Touch relocate backup")
struct TouchRelocationTests {
    static func circled(centerX: Double, centerY: Double, r: Double = 40) -> TouchRelocation {
        var touch = TouchRelocation(viewWidth: 300, viewHeight: 400)
        for i in 0...24 {
            let a = 2 * Double.pi * Double(i) / 24
            let p = ScreenPoint(x: centerX + r * cos(a), y: centerY + r * sin(a))
            if i == 0 { touch.begin(at: p) } else { touch.add(p) }
        }
        touch.finish()
        return touch
    }

    @Test func circleBecomesBoundingSourceAndFarThirdsDestination() throws {
        let touch = Self.circled(centerX: 80, centerY: 100) // upper-left area
        let source = try #require(touch.source)
        #expect(abs(source.x - 40) < 1e-9 && abs(source.width - 80) < 1e-9)
        let dest = try #require(touch.destination)
        #expect(dest.width == source.width && dest.height == source.height)
        // Farthest thirds point from upper-left is lower-right (200, 266.7).
        #expect(abs(dest.x + dest.width / 2 - 200) < 1e-6)
        #expect(abs(dest.y + dest.height / 2 - 800.0 / 3) < 1e-6)
    }

    // Break caught: a tap or tiny scribble creating a zero-size copy.
    @Test func tinyStrokeIsRejected() {
        var touch = TouchRelocation(viewWidth: 300, viewHeight: 400)
        touch.begin(at: ScreenPoint(x: 10, y: 10))
        touch.add(ScreenPoint(x: 15, y: 12))
        let finished = touch.finish()
        #expect(!finished)
        #expect(touch.source == nil && touch.stroke.isEmpty)
    }

    // Break caught: dragging the copy partly off-screen.
    @Test func dragIsClampedInsideView() throws {
        var touch = Self.circled(centerX: 150, centerY: 200)
        touch.moveDestination(to: ScreenPoint(x: 1000, y: -50))
        let dest = try #require(touch.destination)
        #expect(dest.x == 300 - dest.width && dest.y == 0)
    }

    @Test func uniformsCopyOriginalAndBlurOnlyWhenAsked() throws {
        let touch = Self.circled(centerX: 80, centerY: 100)
        let on = try #require(touch.uniforms(blurSource: true))
        #expect(on.copyEnabled == 1 && on.blurEnabled == 1)
        #expect(on.sourceOrigin == SIMD2<Float>(Float(40.0 / 300), Float(60.0 / 400)))
        #expect(on.blurCenter == SIMD2<Float>(Float(80.0 / 300), Float(100.0 / 400)))
        let off = try #require(touch.uniforms(blurSource: false))
        #expect(off.blurEnabled == 0 && off.copyEnabled == 1)
        #expect(TouchRelocation(viewWidth: 300, viewHeight: 400).uniforms(blurSource: true) == nil)
    }

    @Test func newCircleReplacesPreviousRegion() {
        var touch = Self.circled(centerX: 80, centerY: 100)
        touch.begin(at: ScreenPoint(x: 5, y: 5))
        #expect(touch.source == nil && touch.destination == nil && touch.isDrawing)
    }
}
