@testable import Runtime
import XCTest

private let synchronizedCapturedClosureRawLock = NSLock()
private var _synchronizedCapturedClosureRaw = 0

private var synchronizedCapturedClosureRaw: Int {
    get {
        synchronizedCapturedClosureRawLock.lock()
        defer { synchronizedCapturedClosureRawLock.unlock() }
        return _synchronizedCapturedClosureRaw
    }
    set {
        synchronizedCapturedClosureRawLock.lock()
        defer { synchronizedCapturedClosureRawLock.unlock() }
        _synchronizedCapturedClosureRaw = newValue
    }
}

private let synchronizedNestedFnPtrLock = NSLock()
private var _synchronizedNestedFnPtr = 0

private var synchronizedNestedFnPtr: Int {
    get {
        synchronizedNestedFnPtrLock.lock()
        defer { synchronizedNestedFnPtrLock.unlock() }
        return _synchronizedNestedFnPtr
    }
    set {
        synchronizedNestedFnPtrLock.lock()
        defer { synchronizedNestedFnPtrLock.unlock() }
        _synchronizedNestedFnPtr = newValue
    }
}

private let synchronizedNestedClosureRawLock = NSLock()
private var _synchronizedNestedClosureRaw = 0

private var synchronizedNestedClosureRaw: Int {
    get {
        synchronizedNestedClosureRawLock.lock()
        defer { synchronizedNestedClosureRawLock.unlock() }
        return _synchronizedNestedClosureRaw
    }
    set {
        synchronizedNestedClosureRawLock.lock()
        defer { synchronizedNestedClosureRawLock.unlock() }
        _synchronizedNestedClosureRaw = newValue
    }
}

@_cdecl("runtime_synchronized_success_lambda")
private func runtime_synchronized_success_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 123
}

@_cdecl("runtime_synchronized_failure_lambda")
private func runtime_synchronized_failure_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "synchronized failure")
    return 0
}

@_cdecl("runtime_synchronized_capture_lambda")
private func runtime_synchronized_capture_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    synchronizedCapturedClosureRaw = closureRaw
    outThrown?.pointee = 0
    return 77
}

@_cdecl("runtime_synchronized_reentrant_lambda")
private func runtime_synchronized_reentrant_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let result = kk_synchronized(closureRaw, synchronizedNestedFnPtr, synchronizedNestedClosureRaw, outThrown)
    if outThrown?.pointee ?? 0 != 0 {
        return 0
    }
    return result + 1
}

final class RuntimeSynchronizedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        synchronizedCapturedClosureRaw = 0
        synchronizedNestedFnPtr = 0
        synchronizedNestedClosureRaw = 0
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testSynchronizedReturnsBlockResult() {
        let fn = unsafeBitCast(
            runtime_synchronized_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let result = kk_synchronized(101, fn, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 123)
    }

    func testSynchronizedPropagatesThrownValue() {
        let fn = unsafeBitCast(
            runtime_synchronized_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let result = kk_synchronized(202, fn, 0, &thrown)

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testSynchronizedPassesClosureRawToThunk() {
        synchronizedCapturedClosureRaw = 0
        let fn = unsafeBitCast(
            runtime_synchronized_capture_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let sentinel = 4242
        let result = kk_synchronized(303, fn, sentinel, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 77)
        XCTAssertEqual(synchronizedCapturedClosureRaw, sentinel)
    }

    func testSynchronizedSupportsReentrantLocking() {
        let nestedFn = unsafeBitCast(
            runtime_synchronized_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        synchronizedNestedFnPtr = nestedFn
        synchronizedNestedClosureRaw = 0

        let outerFn = unsafeBitCast(
            runtime_synchronized_reentrant_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let lockKey = 404
        let result = kk_synchronized(lockKey, outerFn, lockKey, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 124)
    }
}
