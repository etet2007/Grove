import Foundation

// Keep disk/process pressure bounded and preserve repository order.
func boundedConcurrentMap<Input, Output>(
    _ inputs: [Input], limit: Int = 3,
    transform: @escaping @Sendable (Input) async -> Output
) async -> [Output] {
    await withTaskGroup(of: (Int, Output).self) { group in
        var next = 0
        var results: [(Int, Output)] = []
        func enqueue() {
            guard next < inputs.count, !Task.isCancelled else { return }
            let index = next
            next += 1
            group.addTask { (index, await transform(inputs[index])) }
        }
        for _ in 0..<min(max(1, limit), inputs.count) { enqueue() }
        while let result = await group.next() {
            results.append(result)
            enqueue()
        }
        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
