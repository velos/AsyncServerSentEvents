import Testing
import Foundation
@testable import AsyncServerSentEvents

extension String {
    var unindented: String {
        let lines = components(separatedBy: "\n")
        let stripped = lines.map { line -> String in
            if line.hasPrefix("    ") {
                return String(line.dropFirst(4))
            }
            return line
        }
        return stripped.joined(separator: "\n")
    }

    var byteStream: AsyncStream<UInt8> {
        var normalized = unindented
        if normalized.hasSuffix("\n") && !normalized.hasSuffix("\n\n") {
            normalized.append("\n")
        }
        return Array(normalized.utf8).byteStream
    }
}

extension [UInt8] {
    var byteStream: AsyncStream<UInt8> {
        AsyncStream { continuation in
            for byte in self {
                continuation.yield(byte)
            }
            continuation.finish()
        }
    }
}

@Suite("Server-Sent Events Parsing")
struct SSEParsingTests {

    @Test("Basic events should parse into Event structs")
    func basicEvents() async throws {
        let bytes = SSETestData.basicEvents.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        let expectedData = """
        simple event
        event with colon inline
          event with many spaces after colon
        """

        // Single event with concatenated data fields
        #expect(events[0].id == nil)
        #expect(events[0].name == nil)
        #expect(events[0].data == expectedData)
    }

    @Test("Events with IDs should parse ID field")
    func eventIds() async throws {
        let bytes = SSETestData.eventIds.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 4)

        // First event - basic ID
        #expect(events[0].id == "1")
        #expect(events[0].data == "event with id")

        // Second event - ID with space
        #expect(events[1].id == "2  ")
        #expect(events[1].data == "event with id and space after id")

        // Third event - empty ID
        #expect(events[2].id == "")
        #expect(events[2].data == "event with empty id")

        // Fourth event - colon-only ID
        #expect(events[3].id == "")
        #expect(events[3].data == "event with just colon id")
    }

    @Test("Named events should parse event field")
    func namedEvents() async throws {
        let bytes = SSETestData.namedEvents.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 3)

        // First event - named with space after colon
        #expect(events[0].name == "custom-name")
        #expect(events[0].data == "named event")

        // Second event - name without space after colon
        #expect(events[1].name == "no-space-name")
        #expect(events[1].data == "named event without space after colon")

        // Third event - empty name
        #expect(events[2].name == "")
        #expect(events[2].data == "event with empty name")
    }

    @Test("Comments should be ignored")
    func comments() async throws {
        let bytes = SSETestData.comments.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        #expect(events.isEmpty)
    }

    @Test("Comment-only blocks should not emit events")
    func commentOnlyEvent() async throws {
        let bytes = SSETestData.commentOnlyEvent.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        #expect(events.isEmpty)
    }

    @Test("Multiple data fields should concatenate with newlines")
    func multipleDataFields() async throws {
        let bytes = SSETestData.multipleDataFields.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        let expectedData = """
        first line
        second line
        third line
        """

        #expect(events[0].data == expectedData)
    }

    @Test("Mixed fields should parse all fields correctly")
    func mixedFields() async throws {
        let bytes = SSETestData.mixedFields.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        #expect(events[0].id == "42")  // First and only ID field
        #expect(events[0].name == "update")  // First and only event field
        #expect(events[0].data == """
        mixed field event
        more data
        """)
    }

    @Test("Data fields with leading spaces should preserve spacing")
    func dataLeadingSpaces() async throws {
        let bytes = SSETestData.dataLeadingSpaces.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(events[0].data == "first line\n one leading space\n  two leading spaces")
    }

    @Test("Special characters should be preserved in all fields")
    func specialCharacters() async throws {
        let bytes = SSETestData.specialCharacters.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        #expect(events[0].data == """
        ↑↓←→♠♣♥♦
        табла
        ⚡☔☀
        """)
    }

    @Test("Complete event should parse all fields")
    func completeEvent() async throws {
        let bytes = SSETestData.completeEvent.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        #expect(events[0].id == "final-test")
        #expect(events[0].name == "complete")
        #expect(events[0].data == """
        first
        second
        third
        """)
    }

    @Test("Empty data fields should create empty events")
    func emptyDataFields() async throws {
        let bytes = SSETestData.emptyDataFields.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(events[0].data == "\n\n")
    }

    @Test("Parser should handle [DONE] data")
    func doneAtEnd() async throws {
        let bytes = SSETestData.doneAtEnd.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 4)

        #expect(events[0].data == #"{"id":"1"}"#)
        #expect(events[1].data == #"{"id":"2"}"#)
        #expect(events[2].data == #"{"id":"3"}"#)
        #expect(events[3].data == "[DONE]")
    }

    @Test("Retry field should update state")
    func retryFieldState() async throws {
        let bytes = SSETestData.retryIntervals.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        _ = try await sse.collect()

        let retryInterval = await sse.state.retryInterval
        #expect(retryInterval == 5000)
    }

    @Test("Last event ID should update state")
    func lastEventIdState() async throws {
        let bytes = SSETestData.lastEventIdUpdates.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(events[0].id == "")

        let lastEventId = await sse.state.lastEventId
        #expect(lastEventId == "")
    }

    @Test("Line endings should handle CR, CRLF, and LF")
    func lineEndingVariants() async throws {
        let bytes = SSETestData.lineEndingVariants.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 5)
        #expect(events[0].data == "first")
        #expect(events[1].data == "second")
        #expect(events[2].data == "third")
        #expect(events[3].data == "fourth")
        #expect(events[4].data == "fifth")
    }

    @Test("Missing trailing blank line should discard final event")
    func noTrailingBlankLine() async throws {
        let bytes = SSETestData.noTrailingBlankLine.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        #expect(events.isEmpty)
    }

    @Test("Events should be Hashable")
    func eventHashable() async throws {
        let event1 = ServerSentEvent(id: "1", name: "test", data: "data")
        let event2 = ServerSentEvent(id: "1", name: "test", data: "data")
        let event3 = ServerSentEvent(id: "2", name: "test", data: "data")

        var eventSet = Set<ServerSentEvent>()
        eventSet.insert(event1)
        eventSet.insert(event2)
        eventSet.insert(event3)

        #expect(eventSet.count == 2)
        #expect(eventSet.contains(event1))
        #expect(eventSet.contains(event3))
    }

    @Test("Whitespace-only lines should be ignored")
    func whitespaceOnlyLines() async throws {
        let bytes = SSETestData.whitespaceOnlyLines.byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(events[0].data == "first event\nsecond event")
    }
}
