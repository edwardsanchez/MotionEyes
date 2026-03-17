# MotionEyes

`MotionEyes` is a SwiftUI tracing toolkit for debugging animation and layout behavior over time.

## Repository Structure

This file documents the Swift package only. For the repository overview and skill documentation, see `../README.md`.

It provides:
- A single, low-friction `View` modifier
- A result-builder DSL for tracing multiple metrics
- Configurable sampling FPS (default `15`)
- Changed-only log emission
- Geometry tracing (`minX`, `minY`, `width`, `height`, etc.)
- Scroll geometry tracing (`contentOffset`, `visibleRect`, `contentSize`, etc.)
- Scalar smoothness scoring for sampled traces (`MotionSmoothness`)
- Scalar stillness validation for sampled traces (`MotionStillness`)
- `Logger` output filterable by subsystem/category

## Installation

Add this package to your app and import `MotionEyes`.

## Quick Start

```swift
import MotionEyes
import SwiftUI

struct DemoView: View {
    @State private var opacity = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.orange)
            .frame(width: 200, height: 120)
            .opacity(opacity)
            .motionTrace("Input Field View", fps: 15) {
                Trace.value("opacity", opacity)
                Trace.geometry(
                    "frame",
                    properties: [.minX, .minY, .width, .height],
                    space: .swiftUI(.global),
                    source: .layout
                )
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 1.0)) {
                    opacity = opacity == 0 ? 1 : 0
                }
            }
    }
}
```

ScrollView-specific tracing:

```swift
ScrollView {
    content
}
.motionTrace("Chat Scroll", fps: 24) {
    Trace.scrollGeometry("scrollMetrics")
}
```

## API

```swift
public extension View {
    func motionTrace(
        _ viewName: String,
        fps: Int = 15,
        engine: MotionTraceEngine = .displayLink,
        enabled: Bool = MotionTraceDefaults.enabled,
        logger: Logger = MotionTraceDefaults.logger,
        @MotionTraceBuilder _ metrics: () -> [MotionTraceMetric]
    ) -> some View
}

public enum Trace {
    static func value<V: MotionTraceValueConvertible>(
        _ propertyName: String,
        _ value: V,
        precision: Int = 3,
        epsilon: Double = 0.0001
    ) -> MotionTraceMetric

    static func geometry(
        _ name: String = "geometry",
        properties: Set<MotionGeometryProperty> = [.minX, .minY, .width, .height],
        space: MotionGeometrySpace = .screen,
        source: MotionGeometrySource = .presentation,
        precision: Int = 2,
        epsilon: Double = 0.1
    ) -> MotionTraceMetric

    static func scrollGeometry(
        _ name: String = "scrollGeometry",
        properties: Set<MotionScrollGeometryProperty> = [
            .contentOffsetX,
            .contentOffsetY,
            .visibleRectMinY,
            .visibleRectHeight,
        ],
        precision: Int = 2,
        epsilon: Double = 0.1
    ) -> MotionTraceMetric
}

public enum MotionSmoothness {
    static func isSmooth(
        _ values: [Double],
        minimumSmoothness: Double = 0.8,
        epsilon: Double = 0.0001
    ) -> Bool

    static func evaluate(
        _ values: [Double],
        epsilon: Double = 0.0001
    ) -> MotionSmoothnessResult
}

public enum MotionStillness {
    static func isStill(
        _ values: [Double],
        maximumMovement: Double = 0.2,
        epsilon: Double = 0.0001
    ) -> Bool

    static func evaluate(
        _ values: [Double],
        epsilon: Double = 0.0001
    ) -> MotionStillnessResult
}
```

Smoothness example:

```swift
let samples = [0.0, 0.08, 0.22, 0.45, 0.71, 0.91, 1.0]
XCTAssertTrue(MotionSmoothness.isSmooth(samples, minimumSmoothness: 0.9))
```

`MotionSmoothness` is a discrete-value continuity heuristic. It is useful in tests for catching abrupt local jumps in traced values, but it does not prove real render-time frame pacing or GPU smoothness. It also intentionally does not reject direction changes or overshoot on its own, so backtracking should be asserted separately when that matters.

Stillness example:

```swift
let samples = [240.0, 240.08, 239.97, 240.11]
XCTAssertTrue(MotionStillness.isStill(samples))
```

`MotionStillness` checks that the full sampled trace stayed within a narrow band. The default `maximumMovement` is `0.2`, which works well for point-based geometry traces when you want "effectively did not move" semantics in tests.

Note: On watchOS, the `Trace.geometry` defaults fall back to `space: .swiftUI(.global)` and `source: .layout` because screen/presentation geometry is unavailable.

## Choosing Geometry APIs

- `Trace.geometry` defaults to `space: .screen` and `source: .presentation` on non-watchOS platforms for user-visible motion. Use explicit layout geometry when you care about SwiftUI layout relationships.
- Use `Trace.geometry(..., space: .swiftUI(...), source: .layout)` for SwiftUI layout frame debugging.
- Use `Trace.geometry(..., space: .window, source: .layout)` for model/layout movement relative to the window.
- Use `Trace.geometry(..., space: .screen, source: .presentation)` for visible on-screen movement during animation.
- Use `Trace.scrollGeometry` for scroll-container state such as content offset, visible rect, insets, and scrollable size.
- It is valid to use both metrics in one trace when a bug combines layout and scrolling behavior.

### Geometry Mode Reference

| Goal | Recommended Metric |
| --- | --- |
| Compare sibling/container layout relationships | `Trace.geometry("frame", space: .swiftUI(.global), source: .layout)` |
| Detect movement relative to app window | `Trace.geometry("frame", space: .window, source: .layout)` |
| Detect visible movement relative to physical screen | `Trace.geometry("frame", space: .screen, source: .presentation)` |

Note: `space: .swiftUI(...)` reports SwiftUI layout coordinates, which can remain stable while presentation-layer motion is still visible.

## Logging

Default logger:
- `subsystem: "MotionEyes"`
- `category: "Trace"`

Console filtering examples:
- `subsystem == "MotionEyes"`
- `category == "Trace"`

Log line format:

```text
[MotionEyes][<View Name>][<Metric Name>] key=value key=value ...
[MotionEyes][<View Name>][<Metric Name>] -- Start <timestamp> --
[MotionEyes][<View Name>][<Metric Name>] -- End <timestamp> -- keyDelta=value keyDelta=value ...
```

Behavior details:
- First sample prints a baseline value line.
- When a metric begins changing, MotionEyes prints `Start` with timestamp.
- While changing, it prints sampled values at the configured FPS.
- On the first stable tick after a change burst (or when tracing stops), MotionEyes prints `End` with timestamp and per-property deltas from the last stable value.

## Demo App

A sample iOS app is available at:

`Examples/MotionEyesDemo/`

Open and run:

1. `Examples/MotionEyesDemo/MotionEyesDemo.xcodeproj`
2. Run the `MotionEyesDemo` scheme in iOS Simulator

The app includes:
- Opacity animation tracing
- Offset/position tracing
- Geometry frame tracing
- Scroll geometry tracing
- Shared controls for FPS, tracing enabled, animation enabled, and view label
