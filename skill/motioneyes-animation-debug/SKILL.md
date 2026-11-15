---
name: motioneyes-animation-debug
description: Diagnose, fix, or validate SwiftUI animation and scroll behavior by temporarily instrumenting views with MotionEyes, capturing console traces over time, and comparing motion data to user intent or test expectations. Use when users report bugs such as wrong direction, premature fade, timing or easing mismatch, unexpected movement, missing movement, incorrect relative movement between views, scroll jumps, scroll restoration drift, content-offset desynchronization, or when they want to turn MotionEyes traces into focused assertions. Prefer Xcode's built-in MCP server for project-aware runtime work, RocketSim for interaction, and CLI log streaming as a fallback; remove only agent-added MotionEyes instrumentation after validation.
---

# MotionEyes Animation Debug

## Overview

Use MotionEyes as temporary observability for SwiftUI animation debugging and regression validation. Instrument targeted values and geometry, capture time-series logs, compare observed motion against expected motion, apply fixes or assertions, re-validate, and clean up all agent-added tracing.

## Use This Skill When

- An animation moves in the wrong direction, starts too late, or ends too early.
- Opacity, offset, or position changes do not match expected timing.
- Two elements drift or desynchronize during a transition.
- ScrollView offsets jump, drift, or fail to restore.
- You need evidence from runtime motion values rather than visual guesses.
- You want to turn MotionEyes traces into UITest or regression assertions for timing, continuity, or backtracking.

## Do Not Use If

- The problem is unrelated to SwiftUI animation or scroll behavior.
- You cannot reproduce the behavior in a simulator or device.

## Agent Behavior Contract

Follow these rules for every run:

1. Confirm the complaint and expected behavior in measurable terms before instrumentation.
2. Add only the minimum traces needed to test the complaint.
3. Prefer Xcode's built-in MCP server for console capture; fall back to CLI log streaming when needed.
4. Use semantic trace names that map directly to the user intent.
5. Preserve all pre-existing MotionEyes instrumentation.
6. Remove only agent-added MotionEyes imports, modifiers, and metrics after validation.
7. Re-run after fixes and verify against logs, not assumptions.
8. Treat continuity, direction, and timing as separate concerns; do not use one heuristic as a proxy for all three.

## Workflow

Follow this exact order:

1. Confirm the complaint and expected behavior in measurable terms.
2. Locate the target view and the state values that drive the animation.
3. Ensure MotionEyes availability; if missing, auto-integrate the MotionEyes package into the app target before continuing.
4. Add temporary `.motionTrace(...)` instrumentation with `Trace.value`, `Trace.geometry`, and (for scroll issues) `Trace.scrollGeometry` metrics named after user intent.
5. Run the app and reproduce the issue.
6. Capture logs through Xcode first; fall back to CLI log streaming if direct console capture is unavailable.
7. Analyze how values evolve over time versus expected behavior or extract a focused sample window for assertions.
8. Implement a fix or add an assertion, rerun, and verify the motion now matches intent.
9. Remove only agent-added MotionEyes imports, modifiers, and trace metrics from this run; never remove user-authored pre-existing MotionEyes code.

## Intent Mapping (Screen vs Layout vs Local)

Choose the geometry mode that matches what the user actually cares about.

- **User-visible/on-screen motion** (phrases like "did it move?", "what the user sees", "slide on screen"):
  - `Trace.geometry(..., space: .screen, source: .presentation)`
- **Layout relationships/spacing** (phrases like "aligned", "spacing", "relative to container", "stays in the same stack position"):
  - `Trace.geometry(..., space: .swiftUI(.global), source: .layout)`
- **Local container relationships** (phrases like "within this card", "inside this stack", "relative to parent bounds"):
  - `Trace.geometry(..., space: .swiftUI(.local), source: .layout)` or a named coordinate space

If you are unsure, start with on-screen motion and add layout geometry only if you need relationships.

## Quick Decision Tree

1. If you need to observe a single value changing over time, start with `Trace.value`.
2. If the user cares about visible on-screen motion, start with `Trace.geometry` using `space: .screen, source: .presentation`.
3. If the issue involves layout relationships or spacing, add `Trace.geometry` with `space: .swiftUI(.global), source: .layout` (or `.local` for local container relationships).
4. If the first geometry trace is flat but the user sees motion, add the complementary geometry mode (layout vs presentation) and compare.
5. If the bug involves scrolling or restoration, use `Trace.scrollGeometry` on the `ScrollView` container.

## Triage-First Playbook

- Fade or visibility mismatch: `Trace.value("opacity", opacity)`.
- Offset or translation issues: `Trace.value("offset", CGPoint(x: offset.width, y: offset.height))`.
- Missing or disputed on-screen motion: `Trace.geometry` in `.screen + .presentation` (add layout if needed).
- Position drift between elements: `Trace.geometry` for both views in the same space that matches intent.
- Timing mismatch: trace the driving state with `Trace.value` plus one geometry metric.
- Scroll jumps or restoration drift: `Trace.scrollGeometry` with `contentOffset` and `visibleRect` metrics.
- Unexpected motion when something should remain still: `Trace.geometry` in `.screen + .presentation`.

## Instrumentation Rules

Add instrumentation only to the minimum set of views needed to test the complaint.

- Use stable, semantic trace names that match the user complaint.
- Set the values to the same name as the property, so it is easier to identify.
- Default to on-screen motion (`.screen + .presentation`) when the user is describing what they see.
- Use layout geometry when the issue is about spacing, alignment, or container/sibling relationships.
- Use scroll geometry tracing when the bug involves `ScrollView` offset, visible region, content size, insets, or restoration behavior.
- Place `Trace.scrollGeometry` on the `ScrollView` container or an immediate descendant bound to the same scroll context.
- If a geometry trace is flat but the user reports motion, add the complementary geometry mode and compare.
- Scroll caveat: layout frames can stay stable while scroll geometry or presentation geometry changes.

Choose geometry mode based on intent:

- Layout relationship in SwiftUI coordinates: `space: .swiftUI(.global), source: .layout`
- Local container relationship: `space: .swiftUI(.local), source: .layout` (or a named coordinate space)
- Window-relative layout motion: `space: .window, source: .layout`
- Physical screen-visible motion: `space: .screen, source: .presentation`

### Example Template

```swift
import MotionEyes
import SwiftUI

struct CardMotionExample: View {
    @State private var opacity = 1.0
    @State private var offset = CGSize.zero

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.orange)
            .frame(width: 180, height: 120)
            .opacity(opacity)
            .offset(offset)
            .motionTrace("Card Motion", fps: 30) {
                Trace.value("opacity", opacity)
                Trace.value("offset", CGPoint(x: offset.width, y: offset.height))
                Trace.geometry(
                    "cardFrame",
                    properties: [.minX, .minY, .width, .height],
                    space: .screen,
                    source: .presentation
                )
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.6)) {
                    opacity = opacity == 1 ? 0.4 : 1
                    offset = offset == .zero ? CGSize(width: 0, height: 36) : .zero
                }
            }
    }
}
```

### Scroll-Focused Template

```swift
ScrollView {
    content
}
.motionTrace("Chat Scroll", fps: 30) {
    Trace.scrollGeometry(
        "scrollMetrics",
        properties: [.contentOffsetY, .visibleRectMinY, .visibleRectHeight]
    )
}
```

## Log Capture

Prefer the `xcode` MCP server for project-aware build, run, and console capture. Use RocketSim to reproduce the animation in Simulator, refreshing its accessibility snapshot after navigation or layout changes.

Fallback CLI when direct console capture is unavailable:

```bash
xcrun simctl spawn booted log stream \
  --style compact \
  --level debug \
  --predicate 'subsystem == "MotionEyes"'
```

## MotionEyes Log Analysis

Use these signatures:

- Value samples: `[MotionEyes][View][Metric] key=value ...`
- Change burst start: `[MotionEyes][View][Metric] -- Start timestamp --`
- Change burst end: `[MotionEyes][View][Metric] -- End timestamp --`

Analyze:

- Direction: sign and trend of sampled values.
- Timing: time delta from intent trigger to first `Start` and to `End`.
- Shape: monotonic change, overshoot, reversals, oscillation, flat segments.
- Relationship: compare two traces over the same time window when behavior is relative.

Do not force fixed thresholds globally; evaluate against the user’s stated expectation.

## Automated Trace Assertions

Use this mode when the user wants a testable pass or fail signal rather than a one-off debugging read.

1. Choose one metric and one component that directly represents the complaint.
2. Isolate the sample window from `Start` to `End` for that specific motion burst.
3. Keep assertion types separate:
   - continuity: abrupt local jumps or freezes
   - direction or monotonicity: whether the trace backtracks
   - timing: whether `Start`, `End`, or duration match expectation
4. For continuity checks, use `MotionSmoothness` on the extracted scalar samples.
5. Treat `MotionSmoothness` as a local continuity heuristic only:
   - good for abrupt mid-curve jumps
   - not proof of render-time frame pacing
   - does not reject overshoot or backtracking on its own
6. If the user cares about “went back on itself,” add a separate monotonicity or reversal assertion.
7. If sample count is too low or timestamps are irregular enough to undermine confidence, say so and escalate to visual analysis.

Threshold guidance:

- Do not hardcode one universal pass value for every animation style.
- Start from the user’s actual intent and tune with a known-good baseline trace when possible.
- Linear or tightly controlled traces can use stricter thresholds than eased or springy motion.

## Verification Checklist

- Trace names map directly to the user complaint.
- Motion `Start` and `End` markers align with the expected interaction timeline.
- Direction, timing, and shape match the expected motion.
- Continuity checks and monotonicity checks are not conflated.
- Relative motion metrics stay within expected deltas.
- The fix is verified by a second log capture.
- Agent-added instrumentation is removed after validation.
- The project still builds after cleanup.

## Cleanup Rules

At the end of every run:

- Remove all MotionEyes instrumentation introduced by the agent during this debugging run.
- Keep all MotionEyes instrumentation that already existed before the run.
- Remove agent-added `import MotionEyes` only if it was added solely for temporary tracing and is no longer needed.
- Confirm code compiles after cleanup.

## Scenarios to Support

- Fade timing bug: trace `opacity` and verify fade begins and ends when expected.
- Wrong direction bug: trace Y-related value and confirm sign and trend match expected motion.
- Relative motion bug: trace two objects and verify their positional relationship over time.
- Scroll jump or restoration bug: trace `Trace.scrollGeometry` on the `ScrollView` and verify `contentOffset` and `visibleRect` progression through navigation and return paths.
- No motion desired: confirm a view remains stable during transitions.
- Regression or UITest assertion: extract a trace burst and assert continuity with `MotionSmoothness`, plus separate timing or monotonicity checks when needed.
- Existing instrumentation safety: preserve user-authored MotionEyes traces.
- MCP unavailable: use CLI log stream and continue analysis.
- Missing package: auto-integrate MotionEyes, then execute normal workflow.

## Reference

Load [references/motioneyes-observability-patterns.md](references/motioneyes-observability-patterns.md) when choosing metrics, interpreting trace behavior, or defining MotionEyes-based assertions.
