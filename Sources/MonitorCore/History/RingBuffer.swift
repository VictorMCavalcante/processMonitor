public struct RingBuffer<T>: Sendable where T: Sendable {
    private var storage: [T] = []
    private var head = 0
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    public mutating func append(_ x: T) {
        if storage.count < capacity {
            storage.append(x)
        } else {
            storage[head] = x
            head = (head + 1) % capacity
        }
    }

    public var elements: [T] {
        Array(storage[head...] + storage[..<head])
    }
}
