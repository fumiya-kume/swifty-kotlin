@testable import Runtime
import XCTest

@_cdecl("runtime_result_adv_success_lambda")
private func runtime_result_adv_success_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 7
}

@_cdecl("runtime_result_adv_failure_lambda")
private func runtime_result_adv_failure_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "advanced failure")
    return 0
}

@_cdecl("runtime_result_adv_transform_lambda")
private func runtime_result_adv_transform_lambda(
    _ closureRaw: Int,
    _ argument: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 11
}

final class RuntimeResultAdvancedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testResultOnSuccessInvokesActionAndReturnsSameResult() {
        var thrown = 0
        let successFn = unsafeBitCast(runtime_result_adv_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let actionFn = unsafeBitCast(runtime_result_adv_transform_lambda as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = kk_runCatching(successFn, 0, &thrown)

        let returned = kk_result_onSuccess(resultRaw, actionFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, resultRaw)
        XCTAssertEqual(kk_result_isSuccess(returned), 1)
    }

    func testResultOnFailureInvokesActionAndReturnsSameResult() {
        var thrown = 0
        let failureFn = unsafeBitCast(runtime_result_adv_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let actionFn = unsafeBitCast(runtime_result_adv_transform_lambda as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = kk_runCatching(failureFn, 0, &thrown)

        let returned = kk_result_onFailure(resultRaw, actionFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, resultRaw)
        XCTAssertEqual(kk_result_isFailure(returned), 1)
    }

    func testResultRecoverTransformsFailureIntoSuccess() {
        var thrown = 0
        let failureFn = unsafeBitCast(runtime_result_adv_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let transformFn = unsafeBitCast(runtime_result_adv_transform_lambda as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = kk_runCatching(failureFn, 0, &thrown)

        let recovered = kk_result_recover(resultRaw, transformFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_result_isSuccess(recovered), 1)
        XCTAssertEqual(kk_result_getOrDefault(recovered, 0), 11)
    }
}
