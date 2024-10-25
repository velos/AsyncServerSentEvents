import Foundation

extension AsyncSequence {
    
    /// Returns an async sequence that emits the longest possible subsequences of the sequence, in order,
    /// around elements that match the provided test. The values returned in the closure are the separators.
    ///
    /// - Parameters:
    ///   - test: A closure that takes a subsequence and returns a subsequence to split on, or nil to indicate that the subsequence should not be split.
    ///   - window: The number of elements to consider in the lookahead.
    ///   - maxSplits: The maximum number of splits to perform.
    ///   - omittingEmptySubsequences: Whether to omit empty subsequences from the result.
    /// - Returns: An async stream of subsequences.
    func split(_ test: ([Element]) -> [Element]?, window: Int = 1, maxSplits: Int = .max, omittingEmptySubsequences: Bool = true) async throws -> AsyncStream<[Element]> where Element: Sendable, Element: Equatable {
        let (stream, continuation) = AsyncStream<[Element]>.makeStream()
        var accumulator: [Element] = []
        var lookahead: [Element] = []
        var splitCount = 0

        for try await element in self {
            lookahead.append(element)
            if lookahead.count > window {
                lookahead.removeFirst()
            }

            accumulator.append(element)

            if let match = test(lookahead), splitCount < maxSplits { // lookahead is a match
                let elements = lookahead.split(separator: match, maxSplits: 1, omittingEmptySubsequences: false)
                var result: [Self.Element] = accumulator.dropLast(elements: lookahead)
                result.append(contentsOf: elements.first ?? [])
                if !result.isEmpty || !omittingEmptySubsequences {
                    continuation.yield(result)
                }

                result.removeAll()
                splitCount += 1

                accumulator = Array(elements.last ?? [])
            }
        }

        if !accumulator.isEmpty || !omittingEmptySubsequences {
            continuation.yield(accumulator)
        }
  
        continuation.finish()
        return stream
    }

    /// Returns an async sequence that emits the longest possible subsequences of the sequence, in order,
    /// around elements that match the provided separator.
    ///
    /// - Parameters:
    ///   - separator: The separator to split on.
    ///   - maxSplits: The maximum number of splits to perform.
    ///   - omittingEmptySubsequences: Whether to omit empty subsequences from the result.
    /// - Returns: An async stream of subsequences.
    func split(separator: Element, maxSplits: Int = .max, omittingEmptySubsequences: Bool = true) async throws -> AsyncStream<[Element]> where Element: Equatable, Element: Sendable {
        try await split({ $0.first == separator ? $0 : nil }, window: 1, maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences)
    }

    /// Returns a sequence that emits the longest possible subsequences of the sequence, in order,
    /// around elements that match the provided separator array.
    ///
    /// - Parameters:
    ///   - separator: The separator array to split on.
    ///   - maxSplits: The maximum number of splits to perform.
    ///   - omittingEmptySubsequences: Whether to omit empty subsequences from the result.
    /// - Returns: An async stream of subsequences.
    func split(separator: [Element], maxSplits: Int = .max, omittingEmptySubsequences: Bool = true) async throws -> AsyncStream<[Element]> where Element: Equatable, Element: Sendable {
        try await split({ $0 == separator ? $0 : nil }, window: separator.count, maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences)
    }
}

extension Array where Element: Equatable {

    /// Drop the last elements from the array if they match the provided elements.
    /// - Parameter elements: The elements to drop.
    /// - Returns: The array with the last elements dropped if they matched.
    func dropLast(elements: [Element]) -> [Element] {
        guard self.suffix(elements.count) == elements else {
            return self
        }
        return Array(self.dropLast(elements.count))
    }
}
