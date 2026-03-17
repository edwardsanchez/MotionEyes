import Foundation
import OSLog

final class MotionTraceCoordinator {
    typealias LogSink = (Logger, String) -> Void

    private struct MetricState {
        var metricName: String
        var precision: Int
        var epsilon: Double
        var current: [String: Double]
        var lastEmitted: [String: Double]?
        var motionStart: [String: Double]?
        var hasBaseline = false
        var isInMotion = false
    }

    private let lock = NSLock()
    private var metricStates: [String: MetricState] = [:]
    private var sampler: any MotionTraceSampler
    private var isRunning = false

    private(set) var viewName: String
    private(set) var fps: Int
    private(set) var engine: MotionTraceEngine
    private(set) var logger: Logger

    private let sink: LogSink

    init(
        viewName: String = "MotionTrace",
        fps: Int = 15,
        engine: MotionTraceEngine = .displayLink,
        logger: Logger = MotionTraceDefaults.logger,
        sink: LogSink? = nil
    ) {
        self.viewName = viewName
        self.fps = MotionTraceFPS.clamp(fps)
        self.engine = engine
        self.logger = logger
        let shouldUseInfoLogs = ProcessInfo.processInfo.arguments.contains("--motioneyes-info-logs")
        self.sink = sink ?? MotionTraceDefaults.sink ?? { logger, message in
            if shouldUseInfoLogs {
                logger.info("\(message, privacy: .public)")
            } else {
                logger.debug("\(message, privacy: .public)")
            }
        }
        self.sampler = MotionTraceSamplerFactory.make(engine: engine, fps: fps)

        self.sampler.onTick = { [weak self] in
            self?.processTick()
        }
    }

    func configure(viewName: String, fps: Int, engine: MotionTraceEngine, logger: Logger) {
        lock.lock()
        self.viewName = viewName
        self.logger = logger
        lock.unlock()
        updateSampling(fps: fps, engine: engine)
    }

    func updateViewName(_ viewName: String) {
        lock.lock()
        self.viewName = viewName
        lock.unlock()
    }

    func updateSampling(fps: Int, engine: MotionTraceEngine) {
        let clampedFPS = MotionTraceFPS.clamp(fps)
        var oldSampler: (any MotionTraceSampler)?
        var newSampler: (any MotionTraceSampler)?
        var shouldStartNewSampler = false

        lock.lock()
        let requiresSamplerRebuild = self.engine != engine
        self.fps = clampedFPS
        self.engine = engine

        if requiresSamplerRebuild {
            let replacementSampler = MotionTraceSamplerFactory.make(engine: engine, fps: clampedFPS)
            oldSampler = sampler
            sampler = replacementSampler
            newSampler = replacementSampler
            shouldStartNewSampler = isRunning
        } else {
            sampler.fps = clampedFPS
        }
        lock.unlock()

        guard let oldSampler, let newSampler else { return }
        oldSampler.stop()
        newSampler.onTick = { [weak self] in
            self?.processTick()
        }

        if shouldStartNewSampler {
            newSampler.start()
        }
    }

    func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        let sampler = self.sampler
        lock.unlock()

        sampler.start()
    }

    func stop() {
        let now = Date()
        var linesToEmit: [String] = []
        var logger = MotionTraceDefaults.logger
        var sampler: (any MotionTraceSampler)?

        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false
        logger = self.logger
        sampler = self.sampler

        for metricID in metricStates.keys.sorted() {
            guard var state = metricStates[metricID] else { continue }
            if state.isInMotion {
                linesToEmit.append(endMarkerLine(viewName: viewName, metricName: state.metricName, timestamp: now, state: state))
                state.isInMotion = false
                state.motionStart = nil
                metricStates[metricID] = state
            }
        }
        lock.unlock()

        sampler?.stop()
        emit(linesToEmit, logger: logger)
    }

    func setActiveMetricIDs(_ ids: Set<String>) {
        let now = Date()
        var linesToEmit: [String] = []
        var logger = MotionTraceDefaults.logger

        lock.lock()
        logger = self.logger

        for (metricID, state) in metricStates where !ids.contains(metricID) && state.isInMotion {
            linesToEmit.append(endMarkerLine(viewName: viewName, metricName: state.metricName, timestamp: now, state: state))
        }

        metricStates = metricStates.filter { ids.contains($0.key) }
        lock.unlock()

        emit(linesToEmit, logger: logger)
    }

    func recordValueComponent(
        metricID: String,
        metricName: String,
        componentName: String,
        value: Double,
        precision: Int,
        epsilon: Double
    ) {
        lock.lock()
        var state = metricStates[metricID] ?? MetricState(
            metricName: metricName,
            precision: max(0, precision),
            epsilon: max(0, epsilon),
            current: [:],
            lastEmitted: nil,
            motionStart: nil
        )

        state.metricName = metricName
        state.precision = max(0, precision)
        state.epsilon = max(0, epsilon)
        state.current[componentName] = value

        metricStates[metricID] = state
        lock.unlock()
    }

    func recordGeometry(
        metricID: String,
        metricName: String,
        components: [String: Double],
        precision: Int,
        epsilon: Double
    ) {
        lock.lock()
        var state = metricStates[metricID] ?? MetricState(
            metricName: metricName,
            precision: max(0, precision),
            epsilon: max(0, epsilon),
            current: [:],
            lastEmitted: nil,
            motionStart: nil
        )

        state.metricName = metricName
        state.precision = max(0, precision)
        state.epsilon = max(0, epsilon)
        state.current = components

        metricStates[metricID] = state
        lock.unlock()
    }

    func processTick() {
        let now = Date()
        var linesToEmit: [String] = []
        var logger = MotionTraceDefaults.logger

        lock.lock()
        logger = self.logger

        for metricID in metricStates.keys.sorted() {
            guard var state = metricStates[metricID], !state.current.isEmpty else {
                continue
            }

            if !state.hasBaseline {
                linesToEmit.append(valueLine(viewName: viewName, state: state))
                state.lastEmitted = state.current
                state.hasBaseline = true
                metricStates[metricID] = state
                continue
            }

            let changed = shouldEmit(current: state.current, previous: state.lastEmitted, epsilon: state.epsilon)

            if changed {
                if !state.isInMotion {
                    linesToEmit.append(markerLine(viewName: viewName, metricName: state.metricName, marker: "Start", timestamp: now))
                    state.motionStart = state.lastEmitted ?? state.current
                    state.isInMotion = true
                }

                linesToEmit.append(valueLine(viewName: viewName, state: state))
                state.lastEmitted = state.current
            } else if state.isInMotion {
                linesToEmit.append(endMarkerLine(viewName: viewName, metricName: state.metricName, timestamp: now, state: state))
                state.isInMotion = false
                state.motionStart = nil
            }

            metricStates[metricID] = state
        }
        lock.unlock()

        emit(linesToEmit, logger: logger)
    }

    private func shouldEmit(current: [String: Double], previous: [String: Double]?, epsilon: Double) -> Bool {
        guard let previous else {
            return true
        }

        if Set(current.keys) != Set(previous.keys) {
            return true
        }

        for (key, currentValue) in current {
            guard let previousValue = previous[key] else {
                return true
            }

            if abs(currentValue - previousValue) > epsilon {
                return true
            }
        }

        return false
    }

    private func valueLine(viewName: String, state: MetricState) -> String {
        let components = state.current
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard let value = state.current[key] else {
                    return nil
                }

                return "\(key)=\(formatted(value, precision: state.precision))"
            }
            .joined(separator: " ")

        return "[MotionEyes][\(viewName)][\(state.metricName)] \(components)"
    }

    private func markerLine(viewName: String, metricName: String, marker: String, timestamp: Date) -> String {
        "[MotionEyes][\(viewName)][\(metricName)] -- \(marker) \(formattedTimestamp(timestamp)) --"
    }

    private func endMarkerLine(viewName: String, metricName: String, timestamp: Date, state: MetricState) -> String {
        let deltas = deltaComponents(state: state)
        guard !deltas.isEmpty else {
            return markerLine(viewName: viewName, metricName: metricName, marker: "End", timestamp: timestamp)
        }

        return markerLine(viewName: viewName, metricName: metricName, marker: "End", timestamp: timestamp) + " " + deltas
    }

    private func deltaComponents(state: MetricState) -> String {
        guard let start = state.motionStart else { return "" }

        let parts = state.current
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard let startValue = start[key], let endValue = state.current[key] else {
                    return nil
                }

                let delta = endValue - startValue
                return "\(key)Delta=\(formatted(delta, precision: state.precision))"
            }

        return parts.joined(separator: " ")
    }

    private func emit(_ lines: [String], logger: Logger) {
        guard !lines.isEmpty else { return }
        for line in lines {
            sink(logger, line)
        }
    }

    private func formatted(_ value: Double, precision: Int) -> String {
        String(format: "%.*f", max(0, precision), value)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
