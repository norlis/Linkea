import Foundation
import Testing
@testable import Linkea

struct LoggingTests {
    private let epoch = Date(timeIntervalSince1970: 0)

    private func decode(_ line: String) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(line.utf8))
    }

    @Test func emitsSingleLineJSONWithECSFieldNames() throws {
        let line = AppLog.encodeLine(timestamp: epoch, level: .info, message: "unit test event", fields: ["url.domain": "example.com"], error: nil)
        #expect(!line.contains("\n"))
        let payload = try decode(line)
        #expect(payload["@timestamp"] == "1970-01-01T00:00:00Z")
        #expect(payload["log.level"] == "info")
        #expect(payload["message"] == "unit test event")
        #expect(payload["url.domain"] == "example.com")
    }

    @Test func omitsErrorObjectWhenThereIsNoError() throws {
        let line = AppLog.encodeLine(timestamp: epoch, level: .warn, message: "unit test event", fields: [:], error: nil)
        let payload = try decode(line)
        #expect(payload["error.type"] == nil)
        #expect(payload["error.message"] == nil)
    }

    @Test func includesStructuredErrorObjectWhenPresent() throws {
        let detail = AppLog.ErrorDetail(type: "URLError", message: "connection reset")
        let line = AppLog.encodeLine(timestamp: epoch, level: .error, message: "unit test event", fields: [:], error: detail)
        let payload = try decode(line)
        #expect(payload["log.level"] == "error")
        #expect(payload["error.type"] == "URLError")
        #expect(payload["error.message"] == "connection reset")
    }

    @Test func reservedKeysWinOverCallerProvidedFields() throws {
        let line = AppLog.encodeLine(timestamp: epoch, level: .debug, message: "unit test event", fields: ["message": "spoofed", "log.level": "error"], error: nil)
        let payload = try decode(line)
        #expect(payload["message"] == "unit test event")
        #expect(payload["log.level"] == "debug")
    }

    @Test func nsErrorDetailUsesItsLocalizedDescription() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: [NSLocalizedDescriptionKey: "file missing"])
        let detail = AppLog.errorDetail(from: error)
        #expect(detail.type == "NSError")
        #expect(detail.message == "file missing")
    }

    @Test func plainSwiftErrorDetailKeepsTheCaseNameInsteadOfAGenericSentence() {
        enum ParseFailure: Error { case unreadable }
        let detail = AppLog.errorDetail(from: ParseFailure.unreadable)
        #expect(detail.type == "ParseFailure")
        #expect(detail.message == "unreadable")
    }

    @Test func timestampIsISO8601UTC() throws {
        let line = AppLog.encodeLine(timestamp: Date(timeIntervalSince1970: 1_757_980_800), level: .info, message: "unit test event", fields: [:], error: nil)
        let payload = try decode(line)
        let timestamp = try #require(payload["@timestamp"])
        #expect(timestamp.hasSuffix("Z"))
        #expect(timestamp == "2025-09-16T00:00:00Z")
    }
}
