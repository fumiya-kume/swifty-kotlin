@testable import Runtime
import XCTest

nonisolated(unsafe) private var readWriteLockHandle: Int = 0
nonisolated(unsafe) private var capturedReadClosureRaw: Int = 0

private let readEchoThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, outThrown in
    capturedReadClosureRaw = closureRaw
    outThrown?.pointee = 0
    return closureRaw
}

private let readThrowingThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0xC0DE
    return 0
}

private let readNestedThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, outThrown in
    var innerThrown = 0
    let innerResult = kk_reentrant_read_write_lock_read(
        readWriteLockHandle,
        unsafeBitCast(readEchoThunk, to: Int.self),
        closureRaw + 1,
        &innerThrown
    )
    if innerThrown != 0 {
        outThrown?.pointee = innerThrown
        return 0
    }
    outThrown?.pointee = 0
    return innerResult + 1
}

final class RuntimeReadWriteLockTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        readWriteLockHandle = 0
        capturedReadClosureRaw = 0
    }

    func testConstructorAndReadPassThroughClosureRaw() {
        readWriteLockHandle = kk_reentrant_read_write_lock_new()
        XCTAssertNotEqual(readWriteLockHandle, 0)

        var thrown = 0
        let fnPtr = unsafeBitCast(readEchoThunk, to: Int.self)
        let sentinel = 0x1234
        let result = kk_reentrant_read_write_lock_read(readWriteLockHandle, fnPtr, sentinel, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, sentinel)
        XCTAssertEqual(capturedReadClosureRaw, sentinel)
    }

    func testReadPropagatesThrownValues() {
        readWriteLockHandle = kk_reentrant_read_write_lock_new()
        XCTAssertNotEqual(readWriteLockHandle, 0)

        var thrown = 0
        let fnPtr = unsafeBitCast(readThrowingThunk, to: Int.self)
        let result = kk_reentrant_read_write_lock_read(readWriteLockHandle, fnPtr, 0, &thrown)

        XCTAssertEqual(result, 0)
        XCTAssertEqual(thrown, 0xC0DE)
    }

    func testReadIsReentrantForTheSameHandle() {
        readWriteLockHandle = kk_reentrant_read_write_lock_new()
        XCTAssertNotEqual(readWriteLockHandle, 0)

        capturedReadClosureRaw = 0
        var thrown = 0
        let fnPtr = unsafeBitCast(readNestedThunk, to: Int.self)
        let result = kk_reentrant_read_write_lock_read(readWriteLockHandle, fnPtr, 0x20, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 0x22)
        XCTAssertEqual(capturedReadClosureRaw, 0x21)
    }
}
