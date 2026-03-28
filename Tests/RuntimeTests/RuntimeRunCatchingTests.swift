@testable import Runtime
import XCTest

@_cdecl("runtime_runcatching_success_lambda")
private func runtime_runcatching_success_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 99
}

@_cdecl("runtime_runcatching_failure_lambda")
private func runtime_runcatching_failure_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "runcatching failure")
    return 0
}

final class RuntimeRunCatchingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testRunCatchingWrapsSuccessAsResult() {
        var thrown = 0
        let fn = unsafeBitCast(runtime_runcatching_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = kk_runCatching(fn, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 1)
        XCTAssertEqual(kk_result_isFailure(resultRaw), 0)
        XCTAssertEqual(kk_result_getOrNull(resultRaw), 99)
    }

    func testRunCatchingWrapsFailureWithoutThrowingOutward() {
        var thrown = 0
        let fn = unsafeBitCast(runtime_runcatching_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = kk_runCatching(fn, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 0)
        XCTAssertEqual(kk_result_isFailure(resultRaw), 1)
        XCTAssertNotEqual(kk_result_exceptionOrNull(resultRaw), runtimeNullSentinelInt)
    }
}
