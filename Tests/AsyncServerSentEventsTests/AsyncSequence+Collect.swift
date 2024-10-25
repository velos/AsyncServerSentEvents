import Foundation

extension AsyncSequence {
    func collect() async throws -> [Element] {
        var elements: [Element] = []
        for try await element in self {
            elements.append(element)
        }
        return elements
    }
}