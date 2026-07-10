#if canImport(Darwin)
import Foundation

/// Errors thrown when a server-sent event connection cannot be established.
public enum SSEError: Error, Hashable, Sendable {
    /// The server responded with a status code other than 200.
    case unacceptableStatusCode(Int)

    /// The server responded with a `Content-Type` other than `text/event-stream`.
    case unacceptableContentType(String?)
}

enum SSERequest {
    /// Returns the request with the headers the specification requires an SSE
    /// client to send, without overriding values the caller set explicitly.
    static func prepared(_ request: URLRequest, lastEventId: String? = nil) -> URLRequest {
        var request = request
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        if request.value(forHTTPHeaderField: "Cache-Control") == nil {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        if let lastEventId, !lastEventId.isEmpty {
            request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
        }
        return request
    }

    /// Validates an HTTP response per the specification: status must be 200 and
    /// the content type must be `text/event-stream`. Non-HTTP responses (for
    /// example `file:` URLs) are not validated.
    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else {
            throw SSEError.unacceptableStatusCode(http.statusCode)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        guard let contentType, contentType.lowercased().hasPrefix("text/event-stream") else {
            throw SSEError.unacceptableContentType(contentType)
        }
    }
}

public extension URLSession.AsyncBytes {
    /// Parses these bytes as a server-sent event stream.
    func sse() -> AsyncServerSentEvents<URLSession.AsyncBytes> {
        AsyncServerSentEvents(bytes: self)
    }
}

public extension URLSession {
    /// Opens a server-sent event stream, sending the `Accept: text/event-stream`
    /// header and validating the response status code and content type.
    ///
    /// - Throws: ``SSEError`` if the response is not a 200 `text/event-stream` response.
    func serverSentEvents(from url: URL) async throws -> (AsyncServerSentEvents<URLSession.AsyncBytes>, URLResponse) {
        try await serverSentEvents(for: URLRequest(url: url))
    }

    /// Opens a server-sent event stream, sending the `Accept: text/event-stream`
    /// header and validating the response status code and content type.
    ///
    /// - Throws: ``SSEError`` if the response is not a 200 `text/event-stream` response.
    func serverSentEvents(for request: URLRequest) async throws -> (AsyncServerSentEvents<URLSession.AsyncBytes>, URLResponse) {
        try await serverSentEvents(for: request, delegate: nil)
    }

    /// Opens a server-sent event stream, sending the `Accept: text/event-stream`
    /// header and validating the response status code and content type.
    ///
    /// - Throws: ``SSEError`` if the response is not a 200 `text/event-stream` response.
    func serverSentEvents(from url: URL, delegate: URLSessionTaskDelegate?) async throws -> (AsyncServerSentEvents<URLSession.AsyncBytes>, URLResponse) {
        try await serverSentEvents(for: URLRequest(url: url), delegate: delegate)
    }

    /// Opens a server-sent event stream, sending the `Accept: text/event-stream`
    /// header and validating the response status code and content type.
    ///
    /// - Throws: ``SSEError`` if the response is not a 200 `text/event-stream` response.
    func serverSentEvents(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (AsyncServerSentEvents<URLSession.AsyncBytes>, URLResponse) {
        let (bytes, response) = try await bytes(for: SSERequest.prepared(request), delegate: delegate)
        do {
            try SSERequest.validate(response)
        } catch {
            bytes.task.cancel()
            throw error
        }
        return (bytes.sse(), response)
    }
}
#endif
