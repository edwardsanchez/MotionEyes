public struct MotionStillnessResult: Sendable, Equatable {
    /// Largest observed distance between any two samples in the trace.
    ///
    /// This is the width of the narrowest band that contains the full sampled trace.
    public let movementRange: Double

    /// Largest observed absolute step between adjacent samples.
    public let largestStep: Double

    /// Number of samples that were evaluated.
    public let sampleCount: Int

    public func passes(maximumMovement: Double) -> Bool {
        movementRange <= MotionStillness.clamp(maximumMovement)
    }
}

public enum MotionStillness {
    /// Evaluates whether a sampled scalar trace remained effectively stationary.
    ///
    /// The trace passes when all samples stay within a band no wider than `maximumMovement`.
    /// This is useful for geometry or scroll metrics where a small tolerance should still count
    /// as "did not move" in tests.
    ///
    /// - Parameters:
    ///   - values: Ordered scalar samples from the beginning to the end of the observed segment.
    ///   - maximumMovement: Allowed movement span across the full trace.
    ///   - epsilon: Values smaller than this are treated as unchanged noise.
    /// - Returns: `true` when the sampled trace stayed within `maximumMovement`.
    public static func isStill(
        _ values: [Double],
        maximumMovement: Double = 0.2,
        epsilon: Double = 0.0001
    ) -> Bool {
        evaluate(values, epsilon: epsilon).passes(maximumMovement: maximumMovement)
    }

    /// Computes movement range metrics for a sampled scalar trace.
    ///
    /// Unlike end-point displacement, the reported movement range catches excursions that later
    /// return to the starting value.
    public static func evaluate(
        _ values: [Double],
        epsilon: Double = 0.0001
    ) -> MotionStillnessResult {
        let epsilon = max(0, epsilon)

        guard let firstValue = values.first else {
            return MotionStillnessResult(
                movementRange: 0,
                largestStep: 0,
                sampleCount: 0
            )
        }

        guard values.count > 1 else {
            return MotionStillnessResult(
                movementRange: 0,
                largestStep: 0,
                sampleCount: 1
            )
        }

        var minimumValue = firstValue
        var maximumValue = firstValue
        var previousValue = firstValue
        var largestStep = 0.0

        for value in values.dropFirst() {
            minimumValue = min(minimumValue, value)
            maximumValue = max(maximumValue, value)
            largestStep = max(largestStep, abs(value - previousValue))
            previousValue = value
        }

        let rawMovementRange = maximumValue - minimumValue

        return MotionStillnessResult(
            movementRange: rawMovementRange > epsilon ? rawMovementRange : 0,
            largestStep: largestStep > epsilon ? largestStep : 0,
            sampleCount: values.count
        )
    }

    static func clamp(_ value: Double) -> Double {
        max(value, 0)
    }
}
