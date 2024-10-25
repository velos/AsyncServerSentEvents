import Foundation

public extension URLSession.AsyncBytes {
    func sse() -> AsyncServerSentEvents {
        AsyncServerSentEvents(bytes: self)
    }
}

public extension URLSession {
    func serverSentEvents(from url: URL) async throws -> (AsyncServerSentEvents, URLResponse) {
        let (bytes, response) = try await bytes(from: url)
        return (bytes.sse(), response)
    }

    func serverSentEvents(for request: URLRequest) async throws -> (AsyncServerSentEvents, URLResponse) {
        let (bytes, response) = try await bytes(for: request)
        return (bytes.sse(), response)
    }

    func serverSentEvents(from url: URL, delegate: URLSessionTaskDelegate) async throws -> (AsyncServerSentEvents, URLResponse) {
        let (bytes, response) = try await bytes(from: url, delegate: delegate)
        return (bytes.sse(), response)
    }

    func serverSentEvents(for request: URLRequest, delegate: URLSessionTaskDelegate) async throws -> (AsyncServerSentEvents, URLResponse) {
        let (bytes, response) = try await bytes(for: request, delegate: delegate)
        return (bytes.sse(), response)
    }
}
