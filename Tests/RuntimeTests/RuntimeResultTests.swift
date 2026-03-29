@testable import Runtime
import XCTest

@_cdecl("runtime_result_success_lambda")
private func runtime_result_success_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 42
}

@_cdecl("runtime_result_failure_lambda")
private func runtime_result_failure_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "boom")
    return 0
}

@_cdecl("runtime_result_transform_lambda")
private func runtime_result_transform_lambda(
    _ closureRaw: Int,
    _ argument: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 1
}

final class RuntimeResultTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testResultSuccessStateAndGetOrThrow() {
        var thrown = 0
        let fn = unsafeBitCast(runtime_result_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = kk_runCatching(fn, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 1)
        XCTAssertEqual(kk_result_isFailure(resultRaw), 0)
        XCTAssertEqual(kk_result_getOrThrow(resultRaw, &thrown), 42)
        XCTAssertEqual(thrown, 0)
    }

    func testResultFailureStateAndGetOrThrowRethrows() {
        var thrown = 0
        let fn = unsafeBitCast(runtime_result_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = kk_runCatching(fn, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 0)
        XCTAssertEqual(kk_result_isFailure(resultRaw), 1)
        _ = kk_result_getOrThrow(resultRaw, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testResultGetOrElseUsesFailureTransform() {
        var thrown = 0
        let failureFn = unsafeBitCast(runtime_result_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let transformFn = unsafeBitCast(runtime_result_transform_lambda as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)

        let resultRaw = kk_runCatching(failureFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)

        let fallbackValue = kk_result_getOrElse(resultRaw, transformFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(fallbackValue, 1)
    }
}
