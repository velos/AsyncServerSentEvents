import Testing
import Foundation
@testable import AsyncServerSentEvents

@Suite("Server-Sent Events Spec Compliance")
struct SSESpecComplianceTests {

    @Test("A single leading BOM should be stripped")
    func leadingBOM() async throws {
        let bytes = ([0xEF, 0xBB, 0xBF] + Array("data: hello\n\n".utf8)).byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(events[0].data == "hello")
    }

    @Test("A BOM after the stream start should not be stripped")
    func nonLeadingBOM() async throws {
        let bytes = (Array(":comment\n".utf8) + [0xEF, 0xBB, 0xBF] + Array("data: hello\n\ndata: second\n\n".utf8)).byteStream
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        // "\u{FEFF}data" is not a valid field name, so the first data line is ignored.
        try #require(events.count == 1)
        #expect(events[0].data == "second")
    }

    @Test("Invalid UTF-8 should decode with replacement characters, not fabricate blank lines")
    func invalidUTF8() async throws {
        var input = Array("data: before".utf8)
        input.append(0xFF) // invalid UTF-8 byte
        input.append(contentsOf: Array("after\ndata: second line\n\n".utf8))

        let sse = AsyncServerSentEvents(bytes: input.byteStream)
        let events = try await sse.collect()

        // One event: the invalid byte must not split the block in two.
        try #require(events.count == 1)
        #expect(events[0].data == "before\u{FFFD}after\nsecond line")
    }

    @Test("Errors from the byte stream should be rethrown to the consumer")
    func streamErrorsPropagate() async throws {
        struct TestError: Error {}

        let bytes = AsyncThrowingStream<UInt8, Error> { continuation in
            for byte in Array("data: first\n\ndata: second".utf8) {
                continuation.yield(byte)
            }
            continuation.finish(throwing: TestError())
        }

        let sse = AsyncServerSentEvents(bytes: bytes)
        var received: [ServerSentEvent] = []

        await #expect(throws: TestError.self) {
            for try await event in sse {
                received.append(event)
            }
        }

        // Events dispatched before the failure are still delivered.
        #expect(received.count == 1)
        #expect(received.first?.data == "first")
    }

    @Test("Last event ID should persist onto subsequent events")
    func lastEventIdPersists() async throws {
        let input = "id: 1\ndata: first\n\ndata: second\n\nid: 2\ndata: third\n\n"
        let sse = AsyncServerSentEvents(bytes: Array(input.utf8).byteStream)
        let events = try await sse.collect()

        try #require(events.count == 3)

        #expect(events[0].id == "1")
        #expect(events[0].lastEventId == "1")

        // No explicit id, but the last event ID is inherited.
        #expect(events[1].id == nil)
        #expect(events[1].lastEventId == "1")

        #expect(events[2].id == "2")
        #expect(events[2].lastEventId == "2")
    }

    @Test("An id-only block should commit the last event ID without dispatching")
    func idOnlyBlockCommits() async throws {
        let input = "id: 7\n\ndata: payload\n\n"
        let sse = AsyncServerSentEvents(bytes: Array(input.utf8).byteStream)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(events[0].id == nil)
        #expect(events[0].lastEventId == "7")

        let lastEventId = await sse.state.lastEventId
        #expect(lastEventId == "7")
    }

    @Test("An incomplete final block should not commit its id")
    func incompleteFinalBlockDiscarded() async throws {
        let input = "id: 1\ndata: complete\n\nid: 99\ndata: incomplete"
        let sse = AsyncServerSentEvents(bytes: Array(input.utf8).byteStream)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(events[0].data == "complete")

        let lastEventId = await sse.state.lastEventId
        #expect(lastEventId == "1")
    }

    @Test("Event type should default to message")
    func typeDefaultsToMessage() async throws {
        let input = "data: unnamed\n\nevent:\ndata: empty name\n\nevent: custom\ndata: named\n\n"
        let sse = AsyncServerSentEvents(bytes: Array(input.utf8).byteStream)
        let events = try await sse.collect()

        try #require(events.count == 3)
        #expect(events[0].name == nil)
        #expect(events[0].type == "message")
        #expect(events[1].name == "")
        #expect(events[1].type == "message")
        #expect(events[2].name == "custom")
        #expect(events[2].type == "custom")
    }

    @Test("Consecutive carriage returns should split into distinct lines")
    func consecutiveCarriageReturns() async throws {
        let input = "data: first\r\rdata: second\r\r"
        let sse = AsyncServerSentEvents(bytes: Array(input.utf8).byteStream)
        let events = try await sse.collect()

        try #require(events.count == 2)
        #expect(events[0].data == "first")
        #expect(events[1].data == "second")
    }

    @Test("Cancellation should stop iteration")
    func cancellationStopsIteration() async throws {
        // An endless byte stream that keeps producing events.
        let bytes = AsyncStream<UInt8> { continuation in
            let task = Task {
                let block = Array("data: tick\n\n".utf8)
                while !Task.isCancelled {
                    for byte in block {
                        continuation.yield(byte)
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        let sse = AsyncServerSentEvents(bytes: bytes)
        let consumer = Task {
            var count = 0
            for try await _ in sse {
                count += 1
            }
            return count
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        consumer.cancel()

        // The consumer must finish rather than hang once cancelled.
        _ = try? await consumer.value
    }
}
