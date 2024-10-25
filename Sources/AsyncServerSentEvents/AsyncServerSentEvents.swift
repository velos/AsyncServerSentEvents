// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation

public struct AsyncServerSentEvents: AsyncSequence {
    public typealias Element = Event
    typealias Continuation = AsyncStream<Element>.Continuation

    public struct Event: Hashable, Sendable, Equatable {
        var id: String?
        var name: String?
        var comment: String?
        var data: String

        mutating func appending(commentLine: String) {
            if comment != nil  {
                comment?.append(commentLine + "\n")
            } else if !commentLine.isEmpty {
                comment = commentLine + "\n"
            }
        }

        mutating func appending(dataLine: String) {
            data.append(dataLine + "\n")
        }

        mutating func trim() {
            data = data.trimmingCharacters(in: .whitespacesAndNewlines)
            comment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private let stream: AsyncStream<Element>
    private let continuation: Continuation

    public init(bytes: URLSession.AsyncBytes) {
        (stream, continuation) = AsyncStream<Element>.makeStream()

        Task { [continuation] in
            let lines = try await bytes
                .split({ elements in
                    if elements == [10, 13] {
                        return [10, 13]
                    } else if elements.first == 10 {
                        return [10]
                    } else if elements.first == 13 {
                        return [13]
                    }
                    return nil
                }, window: 2, omittingEmptySubsequences: false)
                .compactMap { String(bytes: $0, encoding: .utf8) }

            var event = Event(data: "")
            for try await line in lines {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if event != Event(data: "") {
                        event.trim()
                        continuation.yield(event)
                    }
                    event = Event(data: "")
                } else {
                    var elements = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    if elements.count == 1 {
                        elements.append("")
                    }

                    let field = elements[0]
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    let value = String(
                        elements[1]
                            .trimmingCharacters(in: .whitespaces)
                    )

                    switch field {
                    case "id":
                        if !value.isEmpty {
                            event.id = value
                        }
                    case "event":
                        if !value.isEmpty {
                            event.name = value
                        }
                    case "":
                        event.appending(commentLine: value)
                    case "data":
                        event.appending(dataLine: value)
                    default:
                        continue
                    }
                }
            }

            if event != Event(data: "") {
                event.trim()
                continuation.yield(event)
            }

            continuation.finish()
        }
    }

    public func makeAsyncIterator() -> AsyncStream<Element>.AsyncIterator {
        stream.makeAsyncIterator()
    }
}
