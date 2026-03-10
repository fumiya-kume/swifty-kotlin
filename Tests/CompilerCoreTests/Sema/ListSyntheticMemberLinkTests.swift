@testable import CompilerCore
import Foundation
import XCTest

final class ListSyntheticMemberLinkTests: XCTestCase {
    func testListTransformMembersUseRuntimeExternalLinksForParameterReceivers() throws {
        let source = """
        fun render(values: List<Int>) {
            values.take(3)
            values.drop(2)
            values.reversed()
            values.sorted()
            values.distinct()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "take": "kk_list_take",
                "drop": "kk_list_drop",
                "reversed": "kk_list_reversed",
                "sorted": "kk_list_sorted",
                "distinct": "kk_list_distinct",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testListAggregateMembersUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let expectedExternalLinks = [
                "sumOf": "kk_list_sumOf",
                "maxOrNull": "kk_list_maxOrNull",
                "minOrNull": "kk_list_minOrNull",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("List"),
                            ctx.interner.intern(memberName),
                        ]
                    ),
                    "Expected synthetic List member \(memberName) to be registered"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: symbolID),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testListConversionMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun convert(values: List<Int>) {
            values.toMutableList()
            values.toSet()
            values.joinToString(", ")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "toMutableList": "kk_list_to_mutable_list",
                "toSet": "kk_list_to_set",
                "joinToString": "kk_list_joinToString",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testMutableListMutationMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.add(1)
            values.removeAt(0)
            values.clear()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "add": "kk_mutable_list_add",
                "removeAt": "kk_mutable_list_removeAt",
                "clear": "kk_mutable_list_clear",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testSetMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun check(values: Set<Int>) {
            values.contains(42)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "contains"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_set_contains",
                "Expected contains to resolve to kk_set_contains"
            )
        }
    }

    func testMutableSetMutationMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableSet<Int>) {
            values.add(1)
            values.remove(1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "add": "kk_mutable_set_add",
                "remove": "kk_mutable_set_remove",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    /// Map member calls (containsKey, put, remove) go through the collection-fallback
    /// inference path which does not record a callBinding. Instead we verify that the
    /// synthetic symbols in the symbol table carry the correct external link names.
    func testMapSyntheticSymbolsHaveCorrectExternalLinkNames() throws {
        let source = """
        fun noop() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let kotlinCollections = ["kotlin", "collections"].map { interner.intern($0) }
            let mapFQ = kotlinCollections + [interner.intern("Map")]
            let mutableMapFQ = kotlinCollections + [interner.intern("MutableMap")]

            let expectedLinks: [(fqName: [InternedString], memberName: String, externalLink: String)] = [
                (mapFQ, "containsKey", "kk_map_contains_key"),
                (mapFQ, "toMutableMap", "kk_map_to_mutable_map"),
                (mutableMapFQ, "put", "kk_mutable_map_put"),
                (mutableMapFQ, "remove", "kk_mutable_map_remove"),
            ]

            for (ownerFQ, memberName, expectedExternal) in expectedLinks {
                let memberFQ = ownerFQ + [interner.intern(memberName)]
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(fqName: memberFQ),
                    "Symbol for \(memberName) not found in symbol table"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: symbolID),
                    expectedExternal,
                    "Expected \(memberName) to have external link \(expectedExternal)"
                )
            }
        }
    }
}
