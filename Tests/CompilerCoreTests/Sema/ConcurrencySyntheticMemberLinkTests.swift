@testable import CompilerCore
import XCTest

final class ConcurrencySyntheticMemberLinkTests: XCTestCase {

    func testThreadClassSyntheticMembersResolve() throws {
        let source = """
        import java.lang.Thread

        fun main() {
            Thread.sleep(1L)
            val current: Thread = Thread.currentThread()
            current.join()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Thread synthetic members should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAtomicArrayHigherOrderAliasesResolve() throws {
        let source = """
        import kotlin.concurrent.atomics.AtomicBooleanArray
        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val ints = AtomicIntArray(1)
            val intOld: Int = ints.getAndUpdateAt(0) { it + 1 }
            val intNew: Int = ints.updateAndGetAt(0) { it + 1 }

            val longs = AtomicLongArray(1)
            val longOld: Long = longs.getAndUpdateAt(0) { it + 1L }
            val longNew: Long = longs.updateAndGetAt(0) { it + 1L }

            val bools = AtomicBooleanArray(1)
            bools.storeAt(0, true)
            val boolOld: Boolean = bools.getAndUpdateAt(0) { !it }
            val boolNew: Boolean = bools.updateAndGetAt(0) { !it }

            println(intOld)
            println(intNew)
            println(longOld)
            println(longNew)
            println(boolOld)
            println(boolNew)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Atomic array higher-order aliases should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testLegacyAtomicBooleanArraySurfaceResolves() throws {
        let source = """
        import kotlin.concurrent.AtomicBooleanArray

        fun main() {
            val values = AtomicBooleanArray(1)
            values.storeAt(0, true)
            val old: Boolean = values.fetchAndUpdateAt(0) { !it }
            println(old)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Legacy AtomicBooleanArray surface should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
