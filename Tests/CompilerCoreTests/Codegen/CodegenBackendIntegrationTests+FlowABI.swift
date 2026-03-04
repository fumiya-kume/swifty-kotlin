@testable import CompilerCore
import XCTest

extension CodegenBackendIntegrationTests {
    func testFixedExternDeclarationsUseFlowABIWithContinuationParameter() {
        let externs = LLVMBackend.fixedExternDeclarations

        XCTAssertTrue(externs.contains("extern intptr_t kk_flow_create(intptr_t emitterFnPtr, intptr_t continuation);"))
        XCTAssertTrue(externs.contains("extern intptr_t kk_flow_emit(intptr_t flowHandle, intptr_t value, intptr_t continuation);"))
        XCTAssertTrue(externs.contains("extern intptr_t kk_flow_collect(intptr_t flowHandle, intptr_t collectorFnPtr, intptr_t continuation);"))

        XCTAssertFalse(externs.contains("extern intptr_t kk_flow_map(intptr_t flowHandle, intptr_t mapFnPtr);"))
        XCTAssertFalse(externs.contains("extern intptr_t kk_flow_filter(intptr_t flowHandle, intptr_t filterFnPtr);"))
        XCTAssertFalse(externs.contains("extern intptr_t kk_flow_take(intptr_t flowHandle, intptr_t count);"))

        XCTAssertFalse(externs.contains("extern intptr_t kk_flow_create(intptr_t emitterFnPtr);"))
        XCTAssertFalse(externs.contains("extern intptr_t kk_flow_emit(intptr_t value);"))
        XCTAssertFalse(externs.contains("extern intptr_t kk_flow_collect(intptr_t flowHandle, intptr_t collectorFnPtr);"))
    }

    func testFixedRuntimePreambleContainsFlowOperatorStubsForNewABI() {
        let preamble = LLVMBackend.fixedRuntimePreamble

        XCTAssertTrue(preamble.contains("__attribute__((weak)) intptr_t kk_flow_create(intptr_t emitterFnPtr, intptr_t continuation) {"))
        XCTAssertTrue(preamble.contains("__attribute__((weak)) intptr_t kk_flow_emit(intptr_t flowHandle, intptr_t value, intptr_t continuation) {"))
        XCTAssertTrue(preamble.contains("__attribute__((weak)) intptr_t kk_flow_collect(intptr_t flowHandle, intptr_t collectorFnPtr, intptr_t continuation) {"))

        XCTAssertFalse(preamble.contains("__attribute__((weak)) intptr_t kk_flow_map(intptr_t flowHandle, intptr_t mapFnPtr) {"))
        XCTAssertFalse(preamble.contains("__attribute__((weak)) intptr_t kk_flow_filter(intptr_t flowHandle, intptr_t filterFnPtr) {"))
        XCTAssertFalse(preamble.contains("__attribute__((weak)) intptr_t kk_flow_take(intptr_t flowHandle, intptr_t count) {"))

        XCTAssertFalse(preamble.contains("__attribute__((weak)) intptr_t kk_flow_create(intptr_t emitterFnPtr) {"))
        XCTAssertFalse(preamble.contains("__attribute__((weak)) intptr_t kk_flow_emit(intptr_t value) {"))
        XCTAssertFalse(preamble.contains("__attribute__((weak)) intptr_t kk_flow_collect(intptr_t flowHandle, intptr_t collectorFnPtr) {"))
    }
}
