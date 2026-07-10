import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AsyncServerSentEvents

@Suite("EventSource")
struct EventSourceTests {

    @Test("EventSource should reconnect with Last-Event-ID and stop on 204")
    func reconnectionAndStop() async throws {
        let server = try TestHTTPServer(responses: [
            .init(body: "id: 1\ndata: first\n\n"),
            .init(body: "retry: 25\nid: 2\ndata: second\n\n"),
            // The script is exhausted after this, so the next connection
            // receives 204 No Content and the sequence ends.
        ])
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/sse")!
        let source = EventSource(url: url, configuration: .init(retryInterval: 25))

        var events: [ServerSentEvent] = []
        for try await event in source {
            events.append(event)
        }

        try #require(events.count == 2)
        #expect(events[0].data == "first")
        #expect(events[0].lastEventId == "1")
        #expect(events[1].data == "second")
        #expect(events[1].lastEventId == "2")

        let requests = server.requests
        try #require(requests.count == 3)
        #expect(requests[0].lowercased().contains("accept: text/event-stream"))
        #expect(!requests[0].lowercased().contains("last-event-id"))
        #expect(requests[1].lowercased().contains("last-event-id: 1"))
        #expect(requests[2].lowercased().contains("last-event-id: 2"))
    }

    @Test("EventSource should fail the connection for non-SSE responses")
    func failsOnWrongContentType() async throws {
        let server = try TestHTTPServer(responses: [
            .init(contentType: "application/json", body: "{}"),
        ])
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/sse")!
        await #expect(throws: SSEError.unacceptableContentType("application/json")) {
            for try await _ in EventSource(url: url) {}
        }
    }
}
