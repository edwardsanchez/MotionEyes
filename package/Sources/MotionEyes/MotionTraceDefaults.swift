import OSLog

public enum MotionTraceDefaults {
    public typealias LogSink = (Logger, String) -> Void

    #if DEBUG
    public static let enabled = true
    #else
    public static let enabled = false
    #endif

    public static let logger = Logger(subsystem: "MotionEyes", category: "Trace")
    public nonisolated(unsafe) static var sink: LogSink?
}
