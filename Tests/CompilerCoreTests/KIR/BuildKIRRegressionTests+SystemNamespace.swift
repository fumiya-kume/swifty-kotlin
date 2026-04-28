@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testGetTimeMicrosLowersToRuntimeCallee() throws {
        let source = """
        import kotlin.system.getTimeMicros

        fun main(): Long = getTimeMicros()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_system_getTimeMicros"), "Expected getTimeMicros runtime call")
        }
    }

    func testGetTimeMillisLowersToRuntimeCallee() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main(): Long = getTimeMillis()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_system_getTimeMillis"), "Expected getTimeMillis runtime call")
        }
    }

    func testGetTimeNanosLowersToRuntimeCallee() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main(): Long = getTimeNanos()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_system_getTimeNanos"), "Expected getTimeNanos runtime call")
        }
    }

    func testSystemObjectMembersLowerToRuntimeCallees() throws {
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

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_system_currentTimeMillis"), "Expected System.currentTimeMillis runtime call")
            XCTAssertTrue(callees.contains("kk_system_nanoTime"), "Expected System.nanoTime runtime call")
            XCTAssertTrue(callees.contains("kk_system_process_start_nanos"), "Expected System.processStartNanos runtime call")
        }
    }

    func testMeasureTimeCallsLowerToClockDeltaRuntimeCallees() throws {
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

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertGreaterThanOrEqual(
                callees.filter { $0 == "kk_system_currentTimeMillis" }.count,
                2,
                "measureTimeMillis should lower to start/end currentTimeMillis calls"
            )
            XCTAssertGreaterThanOrEqual(
                callees.filter { $0 == "kk_system_nanoTime" }.count,
                2,
                "measureNanoTime should lower to start/end nanoTime calls"
            )
            XCTAssertGreaterThanOrEqual(
                callees.filter { $0 == "kk_system_getTimeMicros" }.count,
                2,
                "measureTimeMicros should lower to start/end getTimeMicros calls"
            )
            XCTAssertGreaterThanOrEqual(
                callees.filter { $0 == "kk_op_sub" }.count,
                3,
                "measureTimeMillis, measureTimeMicros, and measureNanoTime should lower to elapsed-time subtraction"
            )
        }
    }
}
