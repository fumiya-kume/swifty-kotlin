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
            values.shuffled()
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
                "shuffled": "kk_list_shuffled",
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

    func testListMaxOrNullAndMinOrNullRequireComparableElements() throws {
        let source = """
        class Box

        fun render(values: List<Box>) {
            values.maxOrNull()
            values.minOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            let boundDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-BOUND" }
            XCTAssertEqual(boundDiagnostics.count, 2, "Expected bound diagnostics for maxOrNull/minOrNull")
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

    func testMutableListSortMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.sort()
            values.sortBy { it }
            values.sortByDescending { it }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
            let expectedExternalLinks = [
                "sort": "kk_mutable_list_sort",
                "sortBy": "kk_mutable_list_sortBy",
                "sortByDescending": "kk_mutable_list_sortByDescending",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                if let chosenCallee = sema.bindings.callBinding(for: callExpr)?.chosenCallee {
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: chosenCallee),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                }
            }
        }
    }

    func testMutableListBulkCollectionMembersAcceptCollectionOfSameElementType() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.addAll(listOf(1, 2))
            values.removeAll(listOf(3, 4))
            values.retainAll(listOf(5, 6))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "addAll": "kk_mutable_list_addAll",
                "removeAll": "kk_mutable_list_removeAll",
                "retainAll": "kk_mutable_list_retainAll",
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

    func testListSortMembersRemainUnavailableOnImmutableList() throws {
        let source = """
        fun mutate(values: List<Int>) {
            values.sort()
            values.sortBy { it }
            values.sortByDescending { it }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            for memberName in ["sort", "sortBy", "sortByDescending"] {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                XCTAssertNil(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected immutable List.\(memberName) to remain unresolved"
                )
            }

            XCTAssertFalse(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected diagnostics for immutable List.sort* calls"
            )
        }
    }
    /// Regression: listOf(...).contains/isEmpty must not emit KSWIFTK-SEMA-VAR-OUT.
    /// The synthetic List type uses .out projection; variance relaxation must apply.
    func testListOfContainsAndIsEmptyDoNotEmitVarOut() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            list.contains(2)
            list.contains(5)
            list.isEmpty()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            var containsCalls: [ExprID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "contains"
                else { continue }
                containsCalls.append(exprID)
            }
            XCTAssertEqual(containsCalls.count, 2)
            for callID in containsCalls {
                let binding = sema.bindings.callBinding(for: callID)
                XCTAssertNotNil(binding?.chosenCallee, "contains should resolve")
                if let chosen = binding?.chosenCallee {
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: chosen),
                        "kk_list_contains",
                        "contains should resolve to kk_list_contains"
                    )
                }
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

    func testContainsMembersAreMarkedOperatorFunctions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let listContains = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("contains"),
            ]))
            let setContains = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
                ctx.interner.intern("contains"),
            ]))
            let stringContains = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("text"),
                ctx.interner.intern("contains"),
            ]))

            XCTAssertTrue(sema.symbols.symbol(listContains)?.flags.contains(.operatorFunction) == true)
            XCTAssertTrue(sema.symbols.symbol(setContains)?.flags.contains(.operatorFunction) == true)
            XCTAssertTrue(sema.symbols.symbol(stringContains)?.flags.contains(.operatorFunction) == true)
        }
    }

    func testWithIndexUsesIterableOfIndexedValueSignature() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let withIndexSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("withIndex"),
            ]))
            let indexedValueSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("IndexedValue"),
            ]))
            let indexedValueRecord = try XCTUnwrap(sema.symbols.symbol(indexedValueSymbol))
            XCTAssertEqual(indexedValueRecord.kind, .class)
            XCTAssertTrue(indexedValueRecord.flags.contains(.dataType))

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: withIndexSymbol))
            guard case let .classType(iterableType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected withIndex() to return Iterable<IndexedValue<T>>")
            }
            XCTAssertEqual(
                try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(iterableType.classSymbol)?.name)),
                "Iterable"
            )
            guard case let .out(elementType) = try XCTUnwrap(iterableType.args.first),
                  case let .classType(indexedValueType) = sema.types.kind(of: elementType)
            else {
                return XCTFail("Expected Iterable element type to be IndexedValue")
            }
            XCTAssertEqual(indexedValueType.classSymbol, indexedValueSymbol)
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
                (mapFQ, "forEach", "kk_map_forEach"),
                (mapFQ, "map", "kk_map_map"),
                (mapFQ, "filter", "kk_map_filter"),
                (mapFQ, "keys", "kk_map_keys"),
                (mapFQ, "values", "kk_map_values"),
                (mapFQ, "entries", "kk_map_entries"),
                (mapFQ, "mapValues", "kk_map_mapValues"),
                (mapFQ, "mapKeys", "kk_map_mapKeys"),
                (mapFQ, "toList", "kk_map_toList"),
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

    func testIndexedAndAggregateListMembersAreInlineSynthetic() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let listFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]

            for memberName in ["sumOf", "forEachIndexed", "mapIndexed"] {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(fqName: listFQName + [ctx.interner.intern(memberName)]),
                    "Expected synthetic List member \(memberName) to be registered"
                )
                let flags = try XCTUnwrap(sema.symbols.symbol(symbolID)?.flags)
                XCTAssertTrue(flags.contains(.inlineFunction), "Expected \(memberName) to be inline")
                XCTAssertTrue(flags.contains(.synthetic), "Expected \(memberName) to be synthetic")
            }
        }
    }

    func testMapHigherOrderMembersAreInlineAndToListPreservesPairType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let mapFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Map"),
            ]

            for memberName in ["forEach", "map", "filter", "mapValues", "mapKeys"] {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(fqName: mapFQName + [ctx.interner.intern(memberName)]),
                    "Expected synthetic Map member \(memberName) to be registered"
                )
                let flags = try XCTUnwrap(sema.symbols.symbol(symbolID)?.flags)
                XCTAssertTrue(flags.contains(.inlineFunction), "Expected \(memberName) to be inline")
            }

            let toListSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: mapFQName + [ctx.interner.intern("toList")])
            )
            let toListSignature = try XCTUnwrap(sema.symbols.functionSignature(for: toListSymbol))
            guard case let .classType(listType) = sema.types.kind(of: toListSignature.returnType) else {
                return XCTFail("Expected Map.toList to return List<Pair<K, V>>")
            }
            let listName = try XCTUnwrap(sema.symbols.symbol(listType.classSymbol)?.name)
            XCTAssertEqual(ctx.interner.resolve(listName), "List")
            let firstListArg = try XCTUnwrap(listType.args.first)
            guard case let .out(pairTypeID) = firstListArg,
                  case let .classType(pairType) = sema.types.kind(of: pairTypeID)
            else {
                return XCTFail("Expected Map.toList element type to be Pair")
            }
            let pairName = try XCTUnwrap(sema.symbols.symbol(pairType.classSymbol)?.name)
            XCTAssertEqual(ctx.interner.resolve(pairName), "Pair")
        }
    }

    func testBuildListInfersElementTypeFromBuilderCalls() throws {
        let source = """
        fun render(): List<Int> = buildList {
            this.add(1)
            add(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildListCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildList"
            })
            let buildListType = try XCTUnwrap(sema.bindings.exprType(for: buildListCall))
            guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                return XCTFail("Expected buildList(...) to produce a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(listType.classSymbol)?.name)), "List")
            guard case let .out(elementType) = try XCTUnwrap(listType.args.first) else {
                return XCTFail("Expected List element type argument")
            }
            XCTAssertEqual(elementType, sema.types.intType)

            let explicitThis = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .thisRef = expr { return true }
                return false
            })
            let explicitThisType = try XCTUnwrap(sema.bindings.exprType(for: explicitThis))
            guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                return XCTFail("Expected builder receiver to be a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(receiverType.classSymbol)?.name)), "MutableList")
            guard case let .invariant(receiverElementType) = try XCTUnwrap(receiverType.args.first) else {
                return XCTFail("Expected MutableList element type argument")
            }
            XCTAssertEqual(receiverElementType, sema.types.intType)
        }
    }

    func testBuildMapInfersKeyAndValueTypesFromBuilderCalls() throws {
        let source = """
        fun render(): Map<String, Int> = buildMap {
            this.put("a", 1)
            put("b", 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildMapCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildMap"
            })
            let buildMapType = try XCTUnwrap(sema.bindings.exprType(for: buildMapCall))
            guard case let .classType(mapType) = sema.types.kind(of: buildMapType) else {
                return XCTFail("Expected buildMap(...) to produce a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(mapType.classSymbol)?.name)), "Map")
            guard mapType.args.count >= 2,
                  case let .out(keyType) = mapType.args[0],
                  case let .out(valueType) = mapType.args[1]
            else {
                return XCTFail("Expected Map key/value type arguments")
            }
            XCTAssertEqual(keyType, sema.types.stringType)
            XCTAssertEqual(valueType, sema.types.intType)

            let explicitThis = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .thisRef = expr { return true }
                return false
            })
            let explicitThisType = try XCTUnwrap(sema.bindings.exprType(for: explicitThis))
            guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                return XCTFail("Expected builder receiver to be a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(receiverType.classSymbol)?.name)), "MutableMap")
            guard receiverType.args.count >= 2,
                  case let .invariant(receiverKeyType) = receiverType.args[0],
                  case let .invariant(receiverValueType) = receiverType.args[1]
            else {
                return XCTFail("Expected MutableMap key/value type arguments")
            }
            XCTAssertEqual(receiverKeyType, sema.types.stringType)
            XCTAssertEqual(receiverValueType, sema.types.intType)
        }
    }

    func testBuildListCapacityOverloadResolves() throws {
        let source = """
        fun render(): List<Int> = buildList(4) {
            add(1)
            add(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildListCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildList"
            })
            let buildListType = try XCTUnwrap(sema.bindings.exprType(for: buildListCall))
            guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                return XCTFail("Expected buildList(capacity) to produce a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(listType.classSymbol)?.name)), "List")
            guard case let .out(elementType) = try XCTUnwrap(listType.args.first) else {
                return XCTFail("Expected List element type argument")
            }
            XCTAssertEqual(elementType, sema.types.intType)
        }
    }
}
