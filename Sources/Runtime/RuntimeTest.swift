import Foundation

// Runtime support for the basic kotlin.test assertion helpers used by STDLIB-TEST-157.

private func runtimeTestDisplayString(from rawValue: Int) -> String {
    if let message = extractString(from: UnsafeMutableRawPointer(bitPattern: rawValue)) {
        return message
    }
    if rawValue == runtimeNullSentinelInt {
        return "null"
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return String(rawValue)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return String(intBox.value)
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return String(longBox.value)
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return String(doubleBox.value)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return String(floatBox.value)
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self),
       let scalar = UnicodeScalar(charBox.value)
    {
        return String(Character(scalar))
    }
    if let throwable = tryCast(pointer, to: RuntimeThrowableBox.self) {
        return throwable.message
    }
    return "<object \(pointer)>"
}

private func runtimeTestNullableMessage(_ rawValue: Int) -> String? {
    if rawValue == runtimeNullSentinelInt || rawValue == 0 {
        return nil
    }
    return runtimeTestDisplayString(from: rawValue)
}

private func runtimeTestFailure(
    message: String,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "AssertionError: \(message)")
    return 0
}

@_cdecl("kk_test_assertEquals")
public func kk_test_assertEquals(
    _ expected: Int,
    _ actual: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard runtimeValuesEqual(expected, actual) else {
        return runtimeTestFailure(
            message: "Expected <\(runtimeTestDisplayString(from: expected))> but was <\(runtimeTestDisplayString(from: actual))>.",
            outThrown
        )
    }
    return 0
}

@_cdecl("kk_test_assertEquals_message")
public func kk_test_assertEquals_message(
    _ expected: Int,
    _ actual: Int,
    _ messageRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard runtimeValuesEqual(expected, actual) else {
        let message = runtimeTestNullableMessage(messageRaw)
            ?? "Expected <\(runtimeTestDisplayString(from: expected))> but was <\(runtimeTestDisplayString(from: actual))>."
        return runtimeTestFailure(message: message, outThrown)
    }
    return 0
}

@_cdecl("kk_test_assertTrue")
public func kk_test_assertTrue(
    _ condition: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard condition != 0 else {
        return runtimeTestFailure(message: "Expected value to be true.", outThrown)
    }
    return 0
}

@_cdecl("kk_test_assertTrue_message")
public func kk_test_assertTrue_message(
    _ condition: Int,
    _ messageRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard condition != 0 else {
        return runtimeTestFailure(
            message: runtimeTestNullableMessage(messageRaw) ?? "Expected value to be true.",
            outThrown
        )
    }
    return 0
}

@_cdecl("kk_test_assertNull")
public func kk_test_assertNull(
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard value == runtimeNullSentinelInt || value == 0 else {
        return runtimeTestFailure(
            message: "Expected value to be null, but was <\(runtimeTestDisplayString(from: value))>.",
            outThrown
        )
    }
    return 0
}

@_cdecl("kk_test_assertNull_message")
public func kk_test_assertNull_message(
    _ value: Int,
    _ messageRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard value == runtimeNullSentinelInt || value == 0 else {
        let message = runtimeTestNullableMessage(messageRaw)
            ?? "Expected value to be null, but was <\(runtimeTestDisplayString(from: value))>."
        return runtimeTestFailure(message: message, outThrown)
    }
    return 0
}

enum RuntimeMockMatcher: Hashable, Sendable {
    case any
    case eq(Int)

    func matches(_ value: Int) -> Bool {
        switch self {
        case .any:
            return true
        case let .eq(expected):
            return value == expected
        }
    }
}

private struct RuntimeMockStubKey: Hashable, Sendable {
    let methodName: String
    let matchers: [RuntimeMockMatcher]

    func matches(methodName: String, arguments: [Int]) -> Bool {
        guard self.methodName == methodName, matchers.count == arguments.count else {
            return false
        }
        for (matcher, value) in zip(matchers, arguments) where !matcher.matches(value) {
            return false
        }
        return true
    }
}

private final class RuntimeMockInvocation: @unchecked Sendable {
    let methodName: String
    let arguments: [Int]

    init(methodName: String, arguments: [Int]) {
        self.methodName = methodName
        self.arguments = arguments
    }
}

private final class RuntimeMockStub: @unchecked Sendable {
    let key: RuntimeMockStubKey
    var returnValues: [Int] = []

    init(key: RuntimeMockStubKey) {
        self.key = key
    }

    func appendReturnValue(_ value: Int) {
        returnValues.append(value)
    }

    func consumeReturnValue() -> Int? {
        guard !returnValues.isEmpty else {
            return nil
        }
        if returnValues.count == 1 {
            return returnValues[0]
        }
        return returnValues.removeFirst()
    }
}

final class RuntimeMockBox: @unchecked Sendable {
    typealias Fallback = (_ methodName: String, _ arguments: [Int]) -> Int

    private let lock = NSLock()
    private let fallback: Fallback?
    private var stubs: [RuntimeMockStub] = []
    private var invocations: [RuntimeMockInvocation] = []

    init(fallback: Fallback? = nil) {
        self.fallback = fallback
    }

    func reset() {
        lock.lock()
        stubs.removeAll(keepingCapacity: true)
        invocations.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func whenever(methodName: String, matchers: [RuntimeMockMatcher]) -> RuntimeMockStubbing {
        lock.lock()
        let stub = RuntimeMockStub(key: RuntimeMockStubKey(methodName: methodName, matchers: matchers))
        stubs.append(stub)
        lock.unlock()
        return RuntimeMockStubbing(box: self, stub: stub)
    }

    func invoke(methodName: String, arguments: [Int]) -> Int {
        lock.lock()
        invocations.append(RuntimeMockInvocation(methodName: methodName, arguments: arguments))

        if let stub = stubs.last(where: { $0.key.matches(methodName: methodName, arguments: arguments) }) {
            let returnValue = stub.consumeReturnValue() ?? 0
            lock.unlock()
            return returnValue
        }

        let fallback = self.fallback
        lock.unlock()
        return fallback?(methodName, arguments) ?? 0
    }

    func verify(methodName: String, matchers: [RuntimeMockMatcher]) -> Int {
        lock.lock()
        let count = invocations.reduce(into: 0) { partialCount, invocation in
            if RuntimeMockStubKey(methodName: methodName, matchers: matchers).matches(
                methodName: invocation.methodName,
                arguments: invocation.arguments
            ) {
                partialCount += 1
            }
        }
        lock.unlock()
        return count
    }

    fileprivate func appendReturnValue(_ value: Int, to stub: RuntimeMockStub) {
        lock.lock()
        stub.appendReturnValue(value)
        lock.unlock()
    }
}

final class RuntimeMockStubbing: @unchecked Sendable {
    private unowned let box: RuntimeMockBox
    private let stub: RuntimeMockStub

    fileprivate init(box: RuntimeMockBox, stub: RuntimeMockStub) {
        self.box = box
        self.stub = stub
    }

    @discardableResult
    func thenReturn(_ value: Int) -> RuntimeMockStubbing {
        box.appendReturnValue(value, to: stub)
        return self
    }
}
