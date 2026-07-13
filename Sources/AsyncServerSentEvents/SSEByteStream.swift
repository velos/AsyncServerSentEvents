import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An `AsyncSequence` of bytes streamed from a `URLSession` data task.
///
/// This is the library's replacement for `URLSession.AsyncBytes`: it is built on
/// `URLSessionDataDelegate`, which is available on Linux as well as Apple
/// platforms. Dropping the sequence (or cancelling the consuming task) cancels
/// the underlying data task.
public struct SSEByteStream: AsyncSequence, @unchecked Sendable {
    public typealias Element = UInt8

    /// The underlying data task, exposed for cancellation.
    public let task: URLSessionDataTask

    let chunks: AsyncThrowingStream<Data, Error>

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(chunks: chunks.makeAsyncIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var chunks: AsyncThrowingStream<Data, Error>.AsyncIterator
        var current: Data = Data()
        var offset = 0

        public mutating func next() async throws -> UInt8? {
            while offset >= current.count {
                guard let chunk = try await chunks.next() else { return nil }
                current = chunk
                offset = 0
            }
            defer { offset += 1 }
            return current[current.startIndex + offset]
        }
    }
}

/// Opens streaming connections through a session-level delegate so that byte
/// streaming works identically on Darwin and Linux.
enum SSEConnection {

    /// Mirrors `URLSession.bytes(for:)`: performs the request on a session
    /// created from the given configuration and returns once the response
    /// headers arrive, exposing the body as a byte stream. The session is
    /// invalidated when the task completes or the stream is dropped.
    static func open(request: URLRequest, configuration: URLSessionConfiguration) async throws -> (SSEByteStream, URLResponse) {
        let delegate = StreamingDelegate()
        let (chunks, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        delegate.dataContinuation = continuation

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)

        continuation.onTermination = { @Sendable _ in
            task.cancel()
            session.finishTasksAndInvalidate()
        }

        let response = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (responseContinuation: CheckedContinuation<URLResponse, Error>) in
                delegate.responseContinuation = responseContinuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }

        return (SSEByteStream(task: task, chunks: chunks), response)
    }

    private final class StreamingDelegate: NSObject, URLSessionDataDelegate {
        // Only mutated from the session's serial delegate queue, except for the
        // initial assignments which happen before the task is resumed.
        var responseContinuation: CheckedContinuation<URLResponse, Error>?
        var dataContinuation: AsyncThrowingStream<Data, Error>.Continuation?

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            responseContinuation?.resume(returning: response)
            responseContinuation = nil
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            dataContinuation?.yield(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let responseContinuation {
                responseContinuation.resume(throwing: error ?? URLError(.badServerResponse))
                self.responseContinuation = nil
            }
            if let error {
                dataContinuation?.finish(throwing: error)
            } else {
                dataContinuation?.finish()
            }
            dataContinuation = nil
            session.finishTasksAndInvalidate()
        }
    }
}
