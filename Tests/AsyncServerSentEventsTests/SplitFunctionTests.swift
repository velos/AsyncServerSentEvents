import Testing
import XCTest
@testable import AsyncServerSentEvents

@Suite("Split Function Tests")
struct SplitFunctionTests {
    
    @Test("Split by single element")
    func testSplitBySingleElement() async throws {
        let sequence = [1, 2, 3, 4, 5, 6, 7, 8, 9].async
        let result = try await sequence.split(separator: 5).collect()
        #expect(result == [[1, 2, 3, 4], [6, 7, 8, 9]])
    }
    
    @Test("Split by array of elements")
    func testSplitByArrayOfElements() async throws {
        let sequence = [1, 2, 3, 4, 3, 5, 6, 7, 8, 9].async
        let result = try await sequence.split(separator: [3, 4]).collect()
        #expect(result == [[1, 2], [3, 5, 6, 7, 8, 9]])
    }
    
    @Test("Split with custom condition")
    func testSplitWithCustomCondition() async throws {
        let sequence = [1, 2, 3, 4, 5, 6, 7, 8, 9].async
        let result = try await sequence.split({ $0.first?.isMultiple(of: 3) == true ? [$0.first!] : nil }, omittingEmptySubsequences: false).collect()
        #expect(result == [[1, 2], [4, 5], [7, 8], []])
    }
    
    @Test("Split empty sequence")
    func testSplitEmptySequence() async throws {
        let emptySequence = [Int]().async
        let result = try await emptySequence.split(separator: 1).collect()
        #expect(result.isEmpty)
    }
    
    @Test("Split with no matches")
    func testSplitWithNoMatches() async throws {
        let sequence = [1, 2, 3, 4, 5].async
        let result = try await sequence.split(separator: 6).collect()
        #expect(result == [[1, 2, 3, 4, 5]])
    }
    
    @Test("Split at the beginning")
    func testSplitAtBeginning() async throws {
        let sequence = [1, 2, 3, 4, 5].async
        let result = try await sequence.split(separator: 1, omittingEmptySubsequences: false).collect()
        #expect(result == [[], [2, 3, 4, 5]])
    }
    
    @Test("Split at the end")
    func testSplitAtEnd() async throws {
        let sequence = [1, 2, 3, 4, 5].async
        let result = try await sequence.split(separator: 5, omittingEmptySubsequences: false).collect()
        #expect(result == [[1, 2, 3, 4], []])
    }
    
    @Test("Split with consecutive separators")
    func testSplitWithConsecutiveSeparators() async throws {
        let sequence = [1, 2, 2, 3, 4, 5].async
        let result = try await sequence.split(separator: 2, omittingEmptySubsequences: false).collect()
        #expect(result == [[1], [], [3, 4, 5]])
    }
    
    @Test("Split with larger window")
    func testSplitWithLargerWindow() async throws {
        let sequence = [1, 2, 3, 4, 5, 6, 7, 8, 9].async
        let result = try await sequence.split({ $0 == [3, 4, 5] ? $0 : nil }, window: 3).collect()
        #expect(result == [[1, 2], [6, 7, 8, 9]])
    }

    @Test("Split with maxSplits")
    func testSplitWithMaxSplits() async throws {
        let sequence = [1, 2, 3, 4, 5, 6, 3, 8, 9].async
        let result = try await sequence.split(separator: 3, maxSplits: 1).collect()
        #expect(result == [[1, 2], [4, 5, 6, 3, 8, 9]])
    }

    @Test("Split string on newlines")
    func testSplitStringOnNewlines() async throws {
        let sequence = try await "Hello\nWorld\nSwift\nAsync".asyncBytes
        let result = try await sequence.split({ elements in
            if elements == [10, 13] {
                return [10, 13]
            } else if elements.first == 10 {
                return [10]
            } else if elements.first == 13 {
                return [13]
            }
            return nil
        }, window: 2, omittingEmptySubsequences: false)
        let values = try await result.collect()
        #expect(values.compactMap { String(bytes: $0, encoding: .utf8) } == ["Hello", "World", "Swift", "Async"])
    }
}

// extension String {
//     var asyncBytes: AsyncStream<UInt8> {
//         AsyncStream { continuation in
//             for byte in self.utf8 {
//                 continuation.yield(byte)
//             }
//             continuation.finish()
//         }
//     }
// }

extension Array where Element: Sendable {
    var async: AsyncStream<Element> {
        AsyncStream { continuation in
            for element in self {
                continuation.yield(element)
            }
            continuation.finish()
        }
    }
}
