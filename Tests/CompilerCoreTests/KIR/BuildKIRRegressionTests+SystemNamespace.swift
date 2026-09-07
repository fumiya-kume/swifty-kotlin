#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    /// KSP-617: getTime* are bundled Kotlin functions, so user code lowers to a
    /// plain Kotlin call — the __kk_system_* bridge is only reached from the
    /// stdlib layer, never inlined into user KIR.
    @Test func testGetTimeMicrosLowersToBundledKotlinCallee() throws {
        let source = """
        import kotlin.system.getTimeMicros

        fun main(): Long = getTimeMicros()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("getTimeMicros"), "Expected a call to the bundled getTimeMicros")
            #expect(!callees.contains("__kk_system_getTimeMicros"), "Bridge must not be called from user KIR")
        }
    }

    @Test func testGetTimeMillisLowersToBundledKotlinCallee() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main(): Long = getTimeMillis()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("getTimeMillis"), "Expected a call to the bundled getTimeMillis")
            #expect(!callees.contains("__kk_system_getTimeMillis"), "Bridge must not be called from user KIR")
        }
    }

    @Test func testGetTimeNanosLowersToBundledKotlinCallee() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main(): Long = getTimeNanos()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("getTimeNanos"), "Expected a call to the bundled getTimeNanos")
            #expect(!callees.contains("__kk_system_getTimeNanos"), "Bridge must not be called from user KIR")
        }
    }

    @Test func testSystemObjectMembersLowerToBundledKotlinCallees() throws {
        let source = """
        import kotlin.system.System

        fun main(): Long {
            val millis = System.currentTimeMillis()
            val nanos = System.nanoTime()
            val startedAt = System.processStartNanos()
            return millis + nanos + startedAt
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("currentTimeMillis"), "Expected System.currentTimeMillis bundled call")
            #expect(callees.contains("nanoTime"), "Expected System.nanoTime bundled call")
            #expect(
                callees.contains("processStartNanos"),
                "Expected System.processStartNanos bundled call"
            )
            for bridge in [
                "__kk_system_currentTimeMillis",
                "__kk_system_nanoTime",
                "__kk_system_process_start_nanos",
            ] {
                #expect(!callees.contains(bridge), "User KIR must not call \(bridge) directly")
            }
        }
    }

    /// KSP-617: measureTime* are bundled Kotlin inline functions, no longer a
    /// KIR special case expanding to paired clock reads.
    @Test func testMeasureTimeCallsLowerToBundledKotlinCallees() throws {
        let source = """
        import kotlin.system.measureNanoTime
        import kotlin.system.measureTimeMicros
        import kotlin.system.measureTimeMillis

        fun main(): Long {
            val millis = measureTimeMillis { }
            val micros = measureTimeMicros { }
            val nanos = measureNanoTime { }
            return millis + micros + nanos
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            for callee in ["measureTimeMillis", "measureTimeMicros", "measureNanoTime"] {
                #expect(callees.contains(callee), "Expected a call to the bundled \(callee)")
            }
            for bridge in [
                "__kk_system_currentTimeMillis", "__kk_system_getTimeMicros", "__kk_system_getTimeNanos",
            ] {
                #expect(!callees.contains(bridge), "\(bridge) must not be inlined into user KIR")
            }
        }
    }

    @Test func testMeasureTimeMillisAcceptsCallableReferenceBlock() throws {
        let source = """
        import kotlin.system.measureTimeMillis

        fun work() {}

        fun main(): Long {
            return measureTimeMillis(::work)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!ctx.diagnostics.hasError, "measureTimeMillis(::work) must type-check")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("measureTimeMillis"))
            #expect(
                callees.contains("kk_callable_ref_tag_kfunction"),
                "The callable reference must be materialised before the call"
            )
        }
    }
}
#endif
