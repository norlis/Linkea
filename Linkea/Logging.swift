import Foundation

/// Structured logger: single-line JSON on stderr with ECS field names, so log lines are
/// machine-parseable without a backing service. Messages stay static; variables go in fields.
/// URLs are never logged whole — they can carry tokens — callers pass scheme/domain fields only.
nonisolated enum AppLog {
    enum Level: String {
        case debug
        case info
        case warn
        case error
    }

    struct ErrorDetail {
        let type: String
        let message: String
    }

    static func debug(_ message: String, fields: [String: String] = [:]) {
        emit(level: .debug, message: message, fields: fields, error: nil)
    }

    static func info(_ message: String, fields: [String: String] = [:]) {
        emit(level: .info, message: message, fields: fields, error: nil)
    }

    static func warn(_ message: String, fields: [String: String] = [:]) {
        emit(level: .warn, message: message, fields: fields, error: nil)
    }

    /// Logs an error exactly once at the point where it is handled, never re-logged upstream.
    static func error(_ message: String, error: (any Error)? = nil, fields: [String: String] = [:]) {
        emit(level: .error, message: message, fields: fields, error: error.map(errorDetail(from:)))
    }

    /// Structured detail for an error. `localizedDescription` on a plain Swift error degrades to
    /// a generic sentence, so those fall back to `String(describing:)`, which keeps the case name.
    static func errorDetail(from error: any Error) -> ErrorDetail {
        let describesItself = error is LocalizedError || Swift.type(of: error) is NSError.Type
        return ErrorDetail(
            type: String(describing: Swift.type(of: error)),
            message: describesItself ? error.localizedDescription : String(describing: error)
        )
    }

    /// Pure encoder, separated from the emitting side effect so tests can pin the timestamp.
    /// Reserved ECS keys win over caller-provided fields on collision.
    static func encodeLine(timestamp: Date, level: Level, message: String, fields: [String: String], error: ErrorDetail?) -> String {
        var payload = fields
        payload["@timestamp"] = timestamp.formatted(.iso8601)
        payload["log.level"] = level.rawValue
        payload["message"] = message
        if let error {
            payload["error.type"] = error.type
            payload["error.message"] = error.message
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload), let line = String(data: data, encoding: .utf8) else {
            return #"{"log.level":"error","message":"log encoding failed"}"#
        }
        return line
    }

    private static func emit(level: Level, message: String, fields: [String: String], error: ErrorDetail?) {
        let line = encodeLine(timestamp: Date(), level: level, message: message, fields: fields, error: error)
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
