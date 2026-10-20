import Testing
@testable import MonitorCore

@Test func keepsOnlyLastNInOrder() {
    var b = RingBuffer<Int>(capacity: 3)
    for i in 1...5 { b.append(i) }
    #expect(b.elements == [3, 4, 5])
}

@Test func emptyAndPartial() {
    var b = RingBuffer<Int>(capacity: 3)
    #expect(b.elements.isEmpty)
    b.append(7)
    #expect(b.elements == [7])
}
