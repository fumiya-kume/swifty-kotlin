@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testNativePlatformMemoryModelLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.Platform

        fun main() {
            val memoryModel = Platform.memoryModel
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_platform_memoryModel"),
                "Expected Platform.memoryModel runtime call"
            )
        }
    }

    func testABILoweringMarksNativePlatformMemoryModelAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(
            callees.contains(interner.intern("kk_platform_memoryModel")),
            "kk_platform_memoryModel should not receive an outThrown slot during ABI lowering"
        )
    }

    func testNativeIdentityHashCodeLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.identityHashCode

        fun probe(value: Any?): Int = value.identityHashCode()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_native_identityHashCode"))
        }
    }

    func testABILoweringMarksNativeIdentityHashCodeAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_native_identityHashCode")))
    }

    func testNativeGetStackTraceAddressesLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.getStackTraceAddresses

        fun probe(): List<Long> = getStackTraceAddresses()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_native_getStackTraceAddresses"))
        }
    }

    func testABILoweringMarksNativeGetStackTraceAddressesAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_native_getStackTraceAddresses")))
    }

    func testNativeUnhandledExceptionHooksLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.getUnhandledExceptionHook
        import kotlin.native.setUnhandledExceptionHook
        import kotlin.native.processUnhandledException
        import kotlin.native.terminateWithUnhandledException

        fun probe(throwable: Throwable) {
            val hook = getUnhandledExceptionHook()
            setUnhandledExceptionHook(hook)
            processUnhandledException(throwable)
        }

        fun die(throwable: Throwable): Nothing = terminateWithUnhandledException(throwable)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let probeBody = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let dieBody = try findKIRFunctionBody(named: "die", in: module, interner: ctx.interner)
            let callees = extractCallees(from: probeBody, interner: ctx.interner)
                + extractCallees(from: dieBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_native_getUnhandledExceptionHook"))
            XCTAssertTrue(callees.contains("kk_native_setUnhandledExceptionHook"))
            XCTAssertTrue(callees.contains("kk_native_processUnhandledException"))
            XCTAssertTrue(callees.contains("kk_native_terminateWithUnhandledException"))
        }
    }

    func testABILoweringMarksNonThrowingNativeUnhandledExceptionHooks() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_native_getUnhandledExceptionHook")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_setUnhandledExceptionHook")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_terminateWithUnhandledException")))
        XCTAssertFalse(callees.contains(interner.intern("kk_native_processUnhandledException")))
    }

    func testNativeByteArrayAccessorsLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.getByteAt
        import kotlin.native.getShortAt
        import kotlin.native.getIntAt
        import kotlin.native.getLongAt

        fun probe(bytes: ByteArray): Long {
            val byteValue = bytes.getByteAt(0)
            val shortValue = bytes.getShortAt(1)
            val intValue = bytes.getIntAt(2)
            return bytes.getLongAt(0) + byteValue + shortValue + intValue
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_native_byteArray_getByteAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_getShortAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_getIntAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_getLongAt"))
        }
    }

    func testABILoweringMarksNativeByteArrayAccessorsAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getByteAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getShortAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getIntAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getLongAt")))
    }

    func testNativeByteArraySettersLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.setByteAt
        import kotlin.native.setShortAt
        import kotlin.native.setIntAt
        import kotlin.native.setLongAt

        fun probe(bytes: ByteArray) {
            bytes.setByteAt(0, -1)
            bytes.setShortAt(1, 0x1234)
            bytes.setIntAt(2, 0x12345678)
            bytes.setLongAt(0, 42L)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_native_byteArray_setByteAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_setShortAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_setIntAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_setLongAt"))
        }
    }

    func testABILoweringMarksNativeByteArraySettersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setByteAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setShortAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setIntAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setLongAt")))
    }

    func testNativeUnsignedByteArrayAccessorsLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

        import kotlin.native.getUByteAt
        import kotlin.native.getUShortAt
        import kotlin.native.getUIntAt
        import kotlin.native.getULongAt

        fun probe(bytes: ByteArray) {
            bytes.getUByteAt(0)
            bytes.getUShortAt(1)
            bytes.getUIntAt(2)
            bytes.getULongAt(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_native_byteArray_getUByteAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_getUShortAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_getUIntAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_getULongAt"))
        }
    }

    func testABILoweringMarksNativeUnsignedByteArrayAccessorsAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getUByteAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getUShortAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getUIntAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getULongAt")))
    }

    func testNativeUnsignedByteArraySettersLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

        import kotlin.native.setUByteAt
        import kotlin.native.setUShortAt
        import kotlin.native.setUIntAt
        import kotlin.native.setULongAt

        fun probe(bytes: ByteArray, ub: UByte, us: UShort, ui: UInt, ul: ULong) {
            bytes.setUByteAt(0, ub)
            bytes.setUShortAt(1, us)
            bytes.setUIntAt(2, ui)
            bytes.setULongAt(0, ul)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_native_byteArray_setUByteAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_setUShortAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_setUIntAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_setULongAt"))
        }
    }

    func testABILoweringMarksNativeUnsignedByteArraySettersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setUByteAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setUShortAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setUIntAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setULongAt")))
    }

    func testNativePrimitiveByteArrayAccessorsLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.getCharAt
        import kotlin.native.getFloatAt
        import kotlin.native.getDoubleAt

        fun probe(bytes: ByteArray) {
            bytes.getCharAt(0)
            bytes.getFloatAt(2)
            bytes.getDoubleAt(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_native_byteArray_getCharAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_getFloatAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_getDoubleAt"))
        }
    }

    func testABILoweringMarksNativePrimitiveByteArrayAccessorsAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getCharAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getFloatAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_getDoubleAt")))
    }

    func testNativePrimitiveByteArraySettersLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.setCharAt
        import kotlin.native.setFloatAt
        import kotlin.native.setDoubleAt

        fun probe(bytes: ByteArray, c: Char, f: Float, d: Double) {
            bytes.setCharAt(0, c)
            bytes.setFloatAt(2, f)
            bytes.setDoubleAt(0, d)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_native_byteArray_setCharAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_setFloatAt"))
            XCTAssertTrue(callees.contains("kk_native_byteArray_setDoubleAt"))
        }
    }

    func testABILoweringMarksNativePrimitiveByteArraySettersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setCharAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setFloatAt")))
        XCTAssertTrue(callees.contains(interner.intern("kk_native_byteArray_setDoubleAt")))
    }
}
