import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A reconnecting server-sent events client modeled on the specification's
/// `EventSource` interface, exposed as an `AsyncSequence` of ``ServerSentEvent``.
///
/// `EventSource` connects with the required `Accept: text/event-stream` header
/// and, like the browser API, automatically reestablishes the connection when
/// the stream ends or a network error occurs:
///
/// - It waits the current reconnection time before each attempt (the server can
///   adjust it with the `retry` field; ``Configuration/retryInterval`` is the default).
/// - It sends the `Last-Event-ID` header with the most recently committed event ID.
/// - An HTTP 204 response ends the sequence normally — the specification's way
///   for a server to tell a client to stop reconnecting.
/// - Any other non-200 status, or a non-`text/event-stream` content type, fails
///   the connection by throwing ``SSEError``.
///
/// Because the stream reconnects on server close, iteration only ends via 204,
/// a thrown error, or cancellation of the consuming task.
///
/// ```swift
/// for try await event in EventSource(url: url) {
///     print(event.type, event.data)
/// }
/// ```
public struct EventSource: AsyncSequence, Sendable {
    public typealias Element = ServerSentEvent

    public struct Configuration: Sendable {
        /// The reconnection delay in milliseconds used until the server provides
        /// one via the `retry` field.
        public var retryInterval: Int

        /// An event ID to resume from on the first connection, sent as the
        /// `Last-Event-ID` header.
        public var lastEventId: String?

        public init(retryInterval: Int = 3000, lastEventId: String? = nil) {
            self.retryInterval = retryInterval
            self.lastEventId = lastEventId
        }
    }

    private let request: URLRequest
    private let session: URLSession
    private let configuration: Configuration

    public init(request: URLRequest, session: URLSession = .shared, configuration: Configuration = Configuration()) {
        self.request = request
        self.session = session
        self.configuration = configuration
    }

    public init(url: URL, session: URLSession = .shared, configuration: Configuration = Configuration()) {
        self.init(request: URLRequest(url: url), session: session, configuration: configuration)
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            request: request,
            session: session,
            retryInterval: configuration.retryInterval,
            lastEventId: configuration.lastEventId
        )
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        let request: URLRequest
        let session: URLSession

        var retryInterval: Int
        var lastEventId: String?

        var current: AsyncServerSentEvents<SSEByteStream>.AsyncIterator?
        var currentState: SSEState?
        var hasAttemptedConnection = false
        var finished = false

        public mutating func next() async throws -> ServerSentEvent? {
            guard !finished else { return nil }

            while true {
                if current == nil {
                    if hasAttemptedConnection {
                        try await Task.sleep(nanoseconds: UInt64(Swift.max(0, retryInterval)) * 1_000_000)
                    }
                    do {
                        try await connect()
                    } catch let error as SSEError {
                        finished = true
                        if case .unacceptableStatusCode(204) = error {
                            return nil
                        }
                        throw error
                    } catch is CancellationError {
                        finished = true
                        throw CancellationError()
                    } catch {
                        // A network error establishing the connection: retry.
                        continue
                    }
                }

                do {
                    if let event = try await current?.next() {
                        if let id = event.lastEventId {
                            lastEventId = id
                        }
                        return event
                    }
                    // The server closed the stream cleanly: reconnect.
                    await prepareForReconnect()
                } catch is CancellationError {
                    finished = true
                    throw CancellationError()
                } catch {
                    // A network error mid-stream: reconnect.
                    await prepareForReconnect()
                }
            }
        }

        private mutating func connect() async throws {
            hasAttemptedConnection = true
            let preparedRequest = SSERequest.prepared(request, lastEventId: lastEventId)
            let (bytes, response) = try await SSEConnection.open(request: preparedRequest, configuration: session.configuration)
            do {
                try SSERequest.validate(response)
            } catch {
                bytes.task.cancel()
                throw error
            }
            let sse = bytes.sse()
            current = sse.makeAsyncIterator()
            currentState = sse.state
        }

        private mutating func prepareForReconnect() async {
            // Pick up retry and id changes from blocks that never dispatched an
            // event (retry-only or id-only blocks).
            if let state = currentState {
                if let interval = await state.retryInterval {
                    retryInterval = interval
                }
                if let id = await state.lastEventId {
                    lastEventId = id
                }
            }
            current = nil
            currentState = nil
        }
    }
}
