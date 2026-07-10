#if canImport(Darwin)
import Testing
import Foundation
@testable import AsyncServerSentEvents

@Suite("URLSession Extension Tests")
struct URLSessionExtensionTests {

    let localFileUrl: URL

    init() throws {
        let tempFile = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
        let body = "data: hello\nid: 123\nevent: message\n\n"
        try body.data(using: .utf8)!.write(to: tempFile)

        localFileUrl = tempFile
    }

    @Test("sse()")
    func testSSE() async throws {
        let (sse, _) = try await URLSession.shared.serverSentEvents(from: localFileUrl)
        let events = try await sse.collect()
        #expect(events.count == 1)
    }

    @Test("serverSentEvents(from:)")
    func testServerSentEventsFrom() async throws {
        let (sse, _) = try await URLSession.shared.serverSentEvents(from: localFileUrl)
        let events = try await sse.collect()
        #expect(events.count == 1)
    }

    @Test("serverSentEvents(for:)")
    func testServerSentEventsFor() async throws {
        let request = URLRequest(url: localFileUrl)
        let (sse, _) = try await URLSession.shared.serverSentEvents(for: request)
        let events = try await sse.collect()
        #expect(events.count == 1)
    }

    @Test("Prepared requests should send SSE headers")
    func preparedRequestHeaders() {
        let request = URLRequest(url: URL(string: "https://example.com/sse")!)
        let prepared = SSERequest.prepared(request, lastEventId: "42")

        #expect(prepared.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(prepared.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
        #expect(prepared.value(forHTTPHeaderField: "Last-Event-ID") == "42")
    }

    @Test("Prepared requests should not override caller-set headers")
    func preparedRequestPreservesHeaders() {
        var request = URLRequest(url: URL(string: "https://example.com/sse")!)
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        let prepared = SSERequest.prepared(request)

        #expect(prepared.value(forHTTPHeaderField: "Accept") == "text/event-stream, application/json")
    }

    @Test("Empty last event ID should not send a Last-Event-ID header")
    func preparedRequestEmptyLastEventId() {
        let request = URLRequest(url: URL(string: "https://example.com/sse")!)
        let prepared = SSERequest.prepared(request, lastEventId: "")

        #expect(prepared.value(forHTTPHeaderField: "Last-Event-ID") == nil)
    }

    @Test("An explicitly cleared last event ID should remove a caller-set header")
    func preparedRequestClearsStaleLastEventId() {
        var request = URLRequest(url: URL(string: "https://example.com/sse")!)
        request.setValue("stale", forHTTPHeaderField: "Last-Event-ID")

        // The stream cleared the ID with an empty id: field.
        let cleared = SSERequest.prepared(request, lastEventId: "")
        #expect(cleared.value(forHTTPHeaderField: "Last-Event-ID") == nil)

        // With no ID tracked at all, the caller's header is left untouched.
        let untouched = SSERequest.prepared(request, lastEventId: nil)
        #expect(untouched.value(forHTTPHeaderField: "Last-Event-ID") == "stale")
    }

    @Test("Response validation should reject non-200 status codes")
    func validationRejectsBadStatus() throws {
        let url = URL(string: "https://example.com/sse")!
        let response = HTTPURLResponse(
            url: url, statusCode: 404, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        #expect(throws: SSEError.unacceptableStatusCode(404)) {
            try SSERequest.validate(response)
        }
    }

    @Test("Response validation should reject wrong content types")
    func validationRejectsBadContentType() throws {
        let url = URL(string: "https://example.com/sse")!
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html"]
        )!

        #expect(throws: SSEError.unacceptableContentType("text/html")) {
            try SSERequest.validate(response)
        }
    }

    @Test("Response validation should reject types that merely share the SSE prefix")
    func validationRejectsPrefixLookalikes() throws {
        let url = URL(string: "https://example.com/sse")!
        for contentType in ["text/event-stream+json", "text/event-streaming"] {
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!

            #expect(throws: SSEError.unacceptableContentType(contentType)) {
                try SSERequest.validate(response)
            }
        }
    }

    @Test("Response validation should accept event streams with parameters")
    func validationAcceptsContentTypeParameters() throws {
        let url = URL(string: "https://example.com/sse")!
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream; charset=utf-8"]
        )!

        try SSERequest.validate(response)
    }

    @Test("Response validation should skip non-HTTP responses")
    func validationSkipsNonHTTP() throws {
        let response = URLResponse(
            url: localFileUrl, mimeType: "text/plain",
            expectedContentLength: 0, textEncodingName: nil
        )

        try SSERequest.validate(response)
    }
}
#endif
