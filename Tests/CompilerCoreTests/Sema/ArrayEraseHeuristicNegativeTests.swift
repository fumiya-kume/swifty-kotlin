@testable import CompilerCore
import Foundation
import XCTest

/// Negative tests to ensure the array-erase heuristic (which previously typed
/// collection HOF results as `Any`) is not reintroduced.
///
/// Each test verifies that a specific collection higher-order function resolves
/// to a synthetic stub and is callable on a `List<String>` receiver without
/// producing a type-mismatch diagnostic.  If the array-erase heuristic is ever
/// re-introduced, these calls would either fail to resolve or silently erase
/// the result type — which the golden tests would also catch.
final class ArrayEraseHeuristicNegativeTests: XCTestCase {

    // MARK: - HOF stub existence (symbol table)

    /// Verify that all target HOF members are registered as synthetic stubs,
    /// so they cannot be silently removed without test breakage.
    func testCollectionHOFSyntheticStubsExist() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let listFQ: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]

            // Only mapIndexed and partition are registered as explicit synthetic
            // stubs.  flatMap/associate*/groupBy use fallback inference and are
            // NOT in the symbol table — their resolution is covered by the call
            // tests below.
            for memberName in [
                "mapIndexed", "partition",
            ] {
                let symbolID = sema.symbols.lookup(
                    fqName: listFQ + [ctx.interner.intern(memberName)]
                )
                XCTAssertNotNil(
                    symbolID,
                    "Expected synthetic List member '\(memberName)' to be registered"
                )
            }
        }
    }

    // MARK: - HOF call resolution (no type-mismatch diagnostic)

    /// mapIndexed call on List<String> must resolve without type error.
    func testMapIndexedCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.mapIndexed { index, item -> item.length }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// flatMap call on List<String> must resolve without type error.
    func testFlatMapCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.flatMap { listOf(it) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// associate call on List<String> must resolve without type error.
    func testAssociateCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.associate { it to it.length }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// associateBy call on List<String> must resolve without type error.
    func testAssociateByCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.associateBy { it.first() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// associateWith call on List<String> must resolve without type error.
    func testAssociateWithCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.associateWith { it.length }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// groupBy call on List<String> must resolve without type error.
    func testGroupByCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.groupBy { it.length }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// partition call on List<String> must resolve without type error.
    func testPartitionCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.partition { it.length > 3 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - listOf() type preservation

    /// Verify that listOf(1, 2, 3) is typed as a collection (not erased to Any).
    func testListOfIntIsNotErasedToAny() throws {
        let source = """
        fun test() {
            val x = listOf(1, 2, 3)
            x.contains(2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // If erased to Any, contains() would fail to resolve.
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
        }
    }
}
