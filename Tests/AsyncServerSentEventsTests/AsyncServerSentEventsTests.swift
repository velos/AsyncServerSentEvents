import Testing
import Foundation
@testable import AsyncServerSentEvents

extension String {
    var asyncBytes: URLSession.AsyncBytes {
        get async throws {
            let tempFile = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
            try data(using: .utf8)!.write(to: tempFile)
            return try await URLSession.shared.bytes(from: tempFile).0
        }
    }
}

@Suite("Server-Sent Events Parsing")
struct SSEParsingTests {

    @Test("Basic events should parse into Event structs")
    func basicEvents() async throws {
        let bytes = try await SSETestData.basicEvents.asyncBytes
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
        #expect(events[0].comment == nil)
        #expect(events[0].data == expectedData)
    }

    @Test("Events with IDs should parse ID field")
    func eventIds() async throws {
        let bytes = try await SSETestData.eventIds.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 4)

        // First event - basic ID
        #expect(events[0].id == "1")
        #expect(events[0].data == "event with id")

        // Second event - ID with space
        #expect(events[1].id == "2")
        #expect(events[1].data == "event with id and space after id")

        // Third event - empty ID
        #expect(events[2].id == nil)
        #expect(events[2].data == "event with empty id")

        // Fourth event - colon-only ID
        #expect(events[3].id == nil)
        #expect(events[3].data == "event with just colon id")
    }

    @Test("Named events should parse event field")
    func namedEvents() async throws {
        let bytes = try await SSETestData.namedEvents.asyncBytes
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
        #expect(events[2].name == nil)
        #expect(events[2].data == "event with empty name")
    }

    @Test("Comments should parse into comment field")
    func comments() async throws {
        let bytes = try await SSETestData.comments.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        // All comments concatenated
        let expectedComment = """
        this is a comment
        this is a comment with space

        :nested comment
        """
        #expect(events[0].comment == expectedComment)  // Last comment in the event
        #expect(events[0].data.isEmpty)  // No data fields
    }

    @Test("Multiple data fields should concatenate with newlines")
    func multipleDataFields() async throws {
        let bytes = try await SSETestData.multipleDataFields.asyncBytes
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
        let bytes = try await SSETestData.mixedFields.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        #expect(events[0].id == "42")  // First and only ID field
        #expect(events[0].name == "update")  // First and only event field
        #expect(events[0].comment == "comment in middle")  // Last comment field
        #expect(events[0].data == """
        mixed field event
        more data
        """)
    }

    @Test("Special characters should be preserved in all fields")
    func specialCharacters() async throws {
        let bytes = try await SSETestData.specialCharacters.asyncBytes
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
        let bytes = try await SSETestData.completeEvent.asyncBytes
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
        let bytes = try await SSETestData.emptyDataFields.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(events[0].data.isEmpty)
    }

    @Test("Parser should handle [DONE] data")
    func doneAtEnd() async throws {
        let bytes = try await SSETestData.doneAtEnd.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 4)

        #expect(events[0].data == #"{"id":"1"}"#)
        #expect(events[1].data == #"{"id":"2"}"#)
        #expect(events[2].data == #"{"id":"3"}"#)
        #expect(events[3].data == "[DONE]")
    }

    @Test("Events should be Hashable")
    func eventHashable() async throws {
        let event1 = AsyncServerSentEvents.Event(id: "1", name: "test", comment: "comment", data: "data")
        let event2 = AsyncServerSentEvents.Event(id: "1", name: "test", comment: "comment", data: "data")
        let event3 = AsyncServerSentEvents.Event(id: "2", name: "test", comment: "comment", data: "data")

        var eventSet = Set<AsyncServerSentEvents.Event>()
        eventSet.insert(event1)
        eventSet.insert(event2)
        eventSet.insert(event3)

        #expect(eventSet.count == 2)
        #expect(eventSet.contains(event1))
        #expect(eventSet.contains(event3))
    }
}
