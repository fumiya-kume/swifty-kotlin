@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testBuildKIRUsesCustomContainerOperatorsForIndexedContainsAndRangeTo() throws {
        let source = """
        class Bucket(private val values: MutableList<Int>) {
            operator fun get(index: Int): Int = values[index]
            operator fun set(index: Int, value: Int) { values[index] = value }
            operator fun contains(value: Int): Boolean = values.any { it == value }
            operator fun rangeTo(other: Bucket): Int = values.size + other.values.size
        }

        fun use(box: Bucket, other: Bucket): Int {
            val value = box[0]
            box[0] = value + 1
            return if (1 in box) box..other else 0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("get"), "Expected custom get call, got: \(callees)")
            XCTAssertTrue(callees.contains("set"), "Expected custom set call, got: \(callees)")
            XCTAssertTrue(callees.contains("contains"), "Expected custom contains call, got: \(callees)")
            XCTAssertTrue(callees.contains("rangeTo"), "Expected custom rangeTo call, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_op_rangeTo"), "Custom rangeTo should not lower to kk_op_rangeTo, got: \(callees)")
        }
    }

    func testBuildKIRUsesCustomIteratorOperatorsInForLoops() throws {
        let source = """
        class Entry(val first: Int, val second: Int) {
            operator fun component1(): Int = first
            operator fun component2(): Int = second
        }

        class EntryIterator(private val values: MutableList<Entry>) {
            private var index = 0
            operator fun hasNext(): Boolean = index < values.size
            operator fun next(): Entry = values[index++]
        }

        class EntryBag(private val values: MutableList<Entry>) {
            operator fun iterator(): EntryIterator = EntryIterator(values)
        }

        fun sumAll(bag: EntryBag): Int {
            var sum = 0
            for ((a, b) in bag) {
                sum += a + b
            }
            return sum
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("iterator"), "Expected custom iterator call, got: \(callees)")
            XCTAssertTrue(callees.contains("hasNext"), "Expected custom hasNext call, got: \(callees)")
            XCTAssertTrue(callees.contains("next"), "Expected custom next call, got: \(callees)")
            XCTAssertTrue(callees.contains("component1"), "Expected destructuring component1 call, got: \(callees)")
            XCTAssertTrue(callees.contains("component2"), "Expected destructuring component2 call, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_range_iterator"), "Custom iterator loop should not use kk_range_iterator, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_range_hasNext"), "Custom iterator loop should not use kk_range_hasNext, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_range_next"), "Custom iterator loop should not use kk_range_next, got: \(callees)")
        }
    }
}
