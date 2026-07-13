import Testing
import Foundation
@testable import AsyncServerSentEvents

@Suite("SSEParser")
struct SSEParserTests {

    /// Every fixture must produce identical events and final state whether it
    /// is parsed synchronously in one buffer or through the async sequence.
    @Test("Synchronous parsing should match the async sequence", arguments: SSETestData.allValidTests + SSETestData.allResilienceTests)
    func matchesAsyncParsing(fixture: String) async throws {
        // Normalize the fixture the same way the async test helper does.
        var input = fixture.unindented
        if input.hasSuffix("\n") && !input.hasSuffix("\n\n") {
            input.append("\n")
        }
        let bytes = Array(input.utf8)

        let sse = AsyncServerSentEvents(bytes: bytes.byteStream)
        let asyncEvents = try await sse.collect()

        var parser = SSEParser()
        let syncEvents = parser.consume(bytes)
        parser.finish()
        let asyncLastEventId = await sse.state.lastEventId
        let asyncRetryInterval = await sse.state.retryInterval

        #expect(syncEvents == asyncEvents)
        #expect(SSEParser.parse(bytes) == asyncEvents)
        #expect(parser.lastEventId == asyncLastEventId)
        #expect(parser.retryInterval == asyncRetryInterval)
    }

    @Test("Chunk boundaries should not affect parsing", arguments: [1, 2, 3, 7, 16, 1024])
    func chunkBoundaryInvariance(chunkSize: Int) {
        let input = "\u{FEFF}id: 1\nevent: tick\ndata: first\ndata: sec:ond\n\nretry: 250\n\nid: 2\r\ndata: é🎉\r\n\r\ndata: dangling"
        let bytes = Array(input.utf8)
        let expected = SSEParser.parse(bytes)

        var parser = SSEParser()
        var events: [ServerSentEvent] = []
        var start = 0
        while start < bytes.count {
            let end = min(start + chunkSize, bytes.count)
            events += parser.consume(bytes[start..<end])
            start = end
        }
        parser.finish()

        #expect(expected.count == 2)
        #expect(events == expected)
        #expect(parser.lastEventId == "2")
        #expect(parser.retryInterval == 250)
    }

    @Test("An event should be emitted on the exact byte completing its block")
    func eventEmittedAtTerminator() {
        var parser = SSEParser()
        for byte in Array("data: hi\n".utf8) {
            #expect(parser.consume(byte) == nil)
        }
        #expect(parser.consume(UInt8(ascii: "\n")) == ServerSentEvent(data: "hi"))
    }

    @Test("Id-only and retry-only blocks should update state without emitting")
    func stateOnlyBlocks() {
        var parser = SSEParser()
        let events = parser.consume(Array("id: 7\n\nretry: 100\n\n".utf8))

        #expect(events.isEmpty)
        #expect(parser.lastEventId == "7")
        #expect(parser.retryInterval == 100)
    }

    @Test("finish should discard the incomplete block but keep reconnect state")
    func finishDiscardsIncompleteBlock() {
        var parser = SSEParser()
        let events = parser.consume(Array("retry: 100\nid: 1\ndata: done\n\nid: 99\ndata: partial".utf8))
        parser.finish()

        #expect(events == [ServerSentEvent(id: "1", data: "done", lastEventId: "1")])
        #expect(parser.lastEventId == "1")
        #expect(parser.retryInterval == 100)
    }

    @Test("A finished parser should handle a fresh stream, including its BOM")
    func reuseAfterFinish() {
        var parser = SSEParser()
        _ = parser.consume(Array("id: 1\ndata: first\n\ndata: partial".utf8))
        parser.finish()

        let events = parser.consume([0xEF, 0xBB, 0xBF] + Array("data: next\n\n".utf8))

        // The new stream starts with a fresh per-stream ID buffer (matching a
        // reconnect), so the event carries no inherited ID, while the parser's
        // committed lastEventId persists for the Last-Event-ID header.
        #expect(events == [ServerSentEvent(data: "next")])
        #expect(parser.lastEventId == "1")
    }

    @Test("A trailing unterminated retry line should take effect at finish")
    func trailingRetryLineApplies() {
        var parser = SSEParser()
        _ = parser.consume(Array("id: 1\ndata: x\n\nid: 9\nretry: 500".utf8))
        parser.finish()

        #expect(parser.retryInterval == 500)
        // The incomplete block's id was never committed by a blank line.
        #expect(parser.lastEventId == "1")
    }

    @Test("A trailing retry line should reach SSEState at end of stream")
    func trailingRetryReachesState() async throws {
        let sse = AsyncServerSentEvents(bytes: Array("data: x\n\nretry: 500".utf8).byteStream)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(await sse.state.retryInterval == 500)
    }

    @Test("A lone data field should dispatch an empty event; no data field should not")
    func emptyDataDispatchRules() {
        var parser = SSEParser()
        let events = parser.consume(Array("data:\n\nevent: named\n\n".utf8))

        // `data:` dispatches an event with empty data; the event-only block
        // dispatches nothing and its name does not leak into later blocks.
        #expect(events == [ServerSentEvent(data: "")])
        #expect(parser.consume(Array("data: after\n\n".utf8)) == [ServerSentEvent(data: "after")])
    }

    @Test("A leading space is removed even before a combining character")
    func leadingSpaceBeforeCombiningCharacter() {
        // U+0301 forms a single grapheme with the preceding space, but the
        // spec's "remove one leading U+0020" rule operates on code points, so
        // the space must still be removed. (A grapheme-based check misses it.)
        var parser = SSEParser()
        let events = parser.consume(Array("data: \u{301}x\n\n".utf8))
        #expect(events == [ServerSentEvent(data: "\u{301}x")])
    }

    @Test("Invalid retry values should be ignored")
    func invalidRetryIgnored() {
        var parser = SSEParser()
        _ = parser.consume(Array("retry: 100\n\nretry: 5s\n\nretry: -1\n\nretry:\n\nretry: 99999999999999999999\n\n".utf8))
        #expect(parser.retryInterval == 100)
    }
}
