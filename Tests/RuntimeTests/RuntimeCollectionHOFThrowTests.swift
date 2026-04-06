import Foundation
@testable import Runtime
import XCTest

private let exceptionID = 12345
private let closeExceptionMessage = "close failure"

private final class CloseableTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var closeCallCount = 0
    private var closeThrowableHandle = 0

    func reset() {
        lock.lock()
        closeCallCount = 0
        closeThrowableHandle = 0
        lock.unlock()
    }

    func configureCloseThrowable(_ handle: Int) {
        lock.lock()
        closeThrowableHandle = handle
        lock.unlock()
    }

    func recordCloseCall() -> Int {
        lock.lock()
        defer { lock.unlock() }
        closeCallCount += 1
        return closeThrowableHandle
    }

    func closeCallCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return closeCallCount
    }
}

private let closeableTestState = CloseableTestState()

private let lambdaThatThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let lambdaThatThrows2: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let blockThrowableMessage = "block failure"

private let closeableBlockThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: blockThrowableMessage)
    return 0
}

private let closeableBlockReturnsValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    77
}

private let closeableCloseThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    let closeThrowable = closeableTestState.recordCloseCall()
    if closeThrowable != 0 {
        outThrown?.pointee = closeThrowable
    }
    return 0
}

private func withCloseableResource(_ body: (Int) -> Void) {
    let typeName = Array("RuntimeTests.CloseableResource\0".utf8).map(CChar.init)
    let fieldOffsets = [UInt32(0)]
    var closeFnRaw = UnsafeRawPointer(bitPattern: unsafeBitCast(closeableCloseThunk, to: Int.self))!

    typeName.withUnsafeBufferPointer { nameBuffer in
        fieldOffsets.withUnsafeBufferPointer { offsetBuffer in
            withUnsafePointer(to: &closeFnRaw) { vtablePointer in
                var typeInfo = KTypeInfo(
                    fqName: nameBuffer.baseAddress!,
                    instanceSize: 0,
                    fieldCount: 0,
                    fieldOffsets: offsetBuffer.baseAddress!,
                    vtableSize: 1,
                    vtable: vtablePointer,
                    itable: nil,
                    gcDescriptor: nil
                )
                withUnsafePointer(to: &typeInfo) { typeInfoPtr in
                    let object = kk_alloc(UInt32(MemoryLayout<KKObjHeader>.size), UnsafeRawPointer(typeInfoPtr))
                    body(Int(bitPattern: object))
                }
            }
        }
    }
}

private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard handle != 0,
          handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle)
    else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

private let groupingByThrowingLambda: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

final class RuntimeCollectionHOFThrowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        closeableTestState.reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }
    
    func testListMapThrows() {
        let array = kk_array_new(3)
        var thrown = 0
        _ = _ = kk_array_set(array, 0, 1, &thrown)
        _ = _ = kk_array_set(array, 1, 2, &thrown)
        _ = _ = kk_array_set(array, 2, 3, &thrown)
        let listWithData = kk_list_of(array, 3)
        
        var outThrown = 0
        let result = kk_list_map(listWithData, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListFilterThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = _ = kk_array_set(array, 0, 1, &thrown)
        let list = kk_list_of(array, 1)
        
        var outThrown = 0
        let result = kk_list_filter(list, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListForEachThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = _ = kk_array_set(array, 0, 1, &thrown)
        let list = kk_list_of(array, 1)
        
        var outThrown = 0
        let result = kk_list_forEach(list, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testArrayMapThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = _ = kk_array_set(array, 0, 1, &thrown)
        
        var outThrown = 0
        let result = kk_array_map(array, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testMapForEachThrows() {
        let map = kk_map_of(kk_array_new(0), kk_array_new(0), 0)
        _ = kk_mutable_map_put(map, 1, 10)
        
        var outThrown = 0
        let result = kk_map_forEach(map, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListReduceEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_reduce(list, 0, 0, &outThrown)
        
        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListFirstEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_first(list, 0, 0, &outThrown)
        
        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListLastEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_last(list, 0, 0, &outThrown)
        
        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListReduceOrNullEmptyDoesNotThrow() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_reduceOrNull(list, 0, 0, &outThrown)

        XCTAssertEqual(outThrown, 0, "reduceOrNull should not throw for empty list")
        XCTAssertEqual(result, runtimeNullSentinelInt, "reduceOrNull should return runtimeNullSentinelInt (null) for empty list")
    }

    func testListScanReduceEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_scanReduce(list, 0, 0, &outThrown)

        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }

    func testListRunningReduceEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_runningReduce(list, 0, 0, &outThrown)

        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }

    func testListFoldThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = _ = kk_array_set(array, 0, 1, &thrown)
        let list = kk_list_of(array, 1)
        
        var outThrown = 0
        let result = kk_list_fold(list, 0, unsafeBitCast(lambdaThatThrows2, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }

    func testUseSuppressesCloseThrowableWhenBlockThrows() {
        let closeThrowable = runtimeAllocateThrowable(message: closeExceptionMessage)
        closeableTestState.configureCloseThrowable(closeThrowable)

        withCloseableResource { resource in
            var outThrown = 0
            let result = kk_use(resource, unsafeBitCast(closeableBlockThrows, to: Int.self), 0, &outThrown)

            XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
            XCTAssertEqual(closeableTestState.closeCallCountSnapshot(), 1)

            guard let blockThrowable = throwableBox(from: outThrown) else {
                XCTFail("Expected block throwable")
                return
            }
            XCTAssertEqual(blockThrowable.message, blockThrowableMessage)
            XCTAssertEqual(blockThrowable.suppressed, [closeThrowable])

            let suppressed = kk_throwable_getSuppressed(outThrown)
            XCTAssertEqual(kk_array_size(suppressed), 1)
            var thrown = 0
            XCTAssertEqual(kk_array_get(suppressed, 0, &thrown), closeThrowable)
            XCTAssertEqual(thrown, 0)
        }
    }

    func testUsePropagatesCloseThrowableWhenBlockSucceeds() {
        let closeThrowable = runtimeAllocateThrowable(message: closeExceptionMessage)
        closeableTestState.configureCloseThrowable(closeThrowable)

        withCloseableResource { resource in
            var outThrown = 0
            let result = kk_use(resource, unsafeBitCast(closeableBlockReturnsValue, to: Int.self), 0, &outThrown)

            XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
            XCTAssertEqual(outThrown, closeThrowable)
            XCTAssertEqual(closeableTestState.closeCallCountSnapshot(), 1)
            guard let closeThrowableBox = throwableBox(from: outThrown) else {
                XCTFail("Expected close throwable")
                return
            }
            XCTAssertEqual(closeThrowableBox.suppressed, [])
        }
    }

    func testGroupingByEachCountThrows() {
        let array = kk_array_new(3)
        var thrown = 0
        _ = _ = kk_array_set(array, 0, 1, &thrown)
        _ = _ = kk_array_set(array, 1, 2, &thrown)
        _ = _ = kk_array_set(array, 2, 3, &thrown)
        let list = kk_list_of(array, 3)
        let grouping = kk_list_groupingBy(list, unsafeBitCast(groupingByThrowingLambda, to: Int.self), 0)

        var outThrown = 0
        let result = kk_grouping_eachCount(grouping, &outThrown)

        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
}
