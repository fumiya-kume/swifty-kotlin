@testable import CompilerCore
import Foundation
import XCTest

/// Mutable-collection, Map, Build, Grouping, and zip/sort/conversion
/// test methods of `ListSyntheticMemberLinkTests`, split out to keep
/// each test source focused.
extension ListSyntheticMemberLinkTests {
    func testListSortedAndSortedDescendingHaveComparableUpperBound() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let baseFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]
            let memberCases: [(String, String)] = [
                ("sorted", "kk_list_sorted"),
                ("sortedDescending", "kk_list_sortedDescending"),
            ]

            for (memberName, externalLinkName) in memberCases {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookupAll(
                        fqName: baseFQName + [ctx.interner.intern(memberName)]
                    ).first(where: { sema.symbols.externalLinkName(for: $0) == externalLinkName }),
                    "Expected synthetic List member \(memberName) to be registered"
                )
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertEqual(signature.typeParameterUpperBoundsList.count, 1)
                let upperBounds = signature.typeParameterUpperBoundsList[0]
                XCTAssertEqual(upperBounds.count, 1, "Expected Comparable upper bound for \(memberName) element type")

                guard case let .classType(boundType) = sema.types.kind(of: upperBounds[0]) else {
                    return XCTFail("Expected \(memberName) upper bound to be a class type")
                }

                XCTAssertEqual(boundType.classSymbol, sema.types.comparableInterfaceSymbol)
                XCTAssertEqual(boundType.args.count, 1)

                guard case let .invariant(argumentType) = boundType.args[0] else {
                    return XCTFail("Expected \(memberName) upper bound to reference invariant element type")
                }

                let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[0],
                    nullability: .nonNull
                )))
                XCTAssertEqual(argumentType, expectedElementType)
            }
        }
    }

    func testListSortedAndSortedDescendingRequireComparableElements() throws {
        let source = """
        class Box

        fun render(values: List<Box>) {
            values.sorted()
            values.sortedDescending()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            let boundDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-BOUND" }
            XCTAssertEqual(boundDiagnostics.count, 2, "Expected bound diagnostics for sorted/sortedDescending")
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
                if memberName == "addAll" {
                    let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("MutableSet"),
                        ctx.interner.intern(memberName),
                    ]))
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: symbol),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                } else {
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
    }

    func testCollectionAndIterableConversionMembersUseRuntimeExternalLinks() throws {
        let cases: [SyntheticMemberCallCase] = [
            .init(
                source: """
                fun copy(values: Collection<String>) {
                    values.toMutableList()
                }
                """,
                memberName: "toMutableList",
                expectedExternalLink: "kk_collection_toMutableList",
                expectedTypeShape: .classNamed("MutableList")
            ),
            .init(
                source: """
                fun copy(values: Collection<String>) {
                    values.toTypedArray()
                }
                """,
                memberName: "toTypedArray",
                expectedExternalLink: "kk_collection_toTypedArray",
                expectedTypeShape: .classNamed("Array")
            ),
            .init(
                source: """
                fun copy(values: Iterable<String>) {
                    values.toMutableList()
                }
                """,
                memberName: "toMutableList",
                expectedExternalLink: "kk_iterable_toMutableList",
                expectedTypeShape: .classNamed("MutableList")
            ),
            .init(
                source: """
                fun copy(values: Iterable<String>) {
                    values.toMutableSet()
                }
                """,
                memberName: "toMutableSet",
                expectedExternalLink: "kk_iterable_toMutableSet",
                expectedTypeShape: .classNamed("MutableSet")
            ),
        ]

        for testCase in cases {
            try assertSyntheticMemberCall(testCase)
        }
    }

    func testSetBinaryMembersKeepSetResultTypeInFallbackPath() throws {
        let source = """
        fun combine(values: Set<Int>, other: Set<Int>) {
            val left = values.intersect(other)
            val middle = values.union(other)
            val right = values.subtract(other)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedMembers = Set(["intersect", "union", "subtract"])
            let setResultTypes: [String: TypeID] = Dictionary(uniqueKeysWithValues: ast.arena.exprs.indices.compactMap { index in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr
                else {
                    return nil
                }
                let memberName = ctx.interner.resolve(callee)
                guard expectedMembers.contains(memberName),
                      let type = sema.bindings.exprType(for: exprID)
                else {
                    return nil
                }
                return (memberName, type)
            })

            XCTAssertEqual(setResultTypes.keys.count, expectedMembers.count)

            for memberName in expectedMembers {
                let type = try XCTUnwrap(setResultTypes[memberName], "Expected inferred type for \(memberName)")
                guard case let .classType(classType) = sema.types.kind(of: type) else {
                    return XCTFail("Expected \(memberName) to infer as Set<Int>, got \(sema.types.kind(of: type))")
                }
                XCTAssertEqual(
                    try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)),
                    "Set"
                )
                XCTAssertEqual(classType.args.count, 1, "Expected Set<Int> type argument for \(memberName)")
                let elementType: TypeID
                switch classType.args[0] {
                case let .invariant(type), let .out(type), let .in(type):
                    elementType = type
                case .star:
                    return XCTFail("Expected concrete Set element projection for \(memberName)")
                }
                XCTAssertEqual(sema.types.kind(of: elementType), .primitive(.int, .nonNull))
            }
        }
    }

    func testListUnzipUsesRuntimeExternalLinkAndReturnsPairOfLists() throws {
        let source = """
        fun split(values: List<Pair<Int, String>>) {
            val result: Pair<List<Int>, List<String>> = values.unzip()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected List.unzip to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "unzip"
            }, "Expected values.unzip() member call in AST")
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_list_unzip")

            let resultType = try XCTUnwrap(sema.bindings.exprType(for: callExpr))
            guard case let .classType(pairType) = sema.types.kind(of: resultType) else {
                return XCTFail("Expected List.unzip to return Pair<List<Int>, List<String>>")
            }
            XCTAssertEqual(
                try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(pairType.classSymbol)?.name)),
                "Pair"
            )
            XCTAssertEqual(pairType.args.count, 2)

            let firstListType = try projectedType(pairType.args[0])
            let secondListType = try projectedType(pairType.args[1])
            try assertListType(firstListType, elementType: sema.types.intType, sema: sema, interner: ctx.interner)
            try assertListType(secondListType, elementType: sema.types.stringType, sema: sema, interner: ctx.interner)
        }
    }

    func testSequenceJoinToStringUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: Sequence<Int>) {
            println(values.joinToString(", "))
            println(values.joinToString(prefix = "<", postfix = ">"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "joinToString"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_sequence_joinToString")
        }
    }

    func testSequenceReduceIndexedOrNullUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: Sequence<Int>) {
            println(values.reduceIndexedOrNull { index, acc, value -> acc + index * value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let sequenceReduceIndexedOrNullSymbol = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("sequences"),
                        ctx.interner.intern("Sequence"),
                        ctx.interner.intern("reduceIndexedOrNull"),
                    ]
                ),
                "Expected synthetic Sequence.reduceIndexedOrNull member to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sequenceReduceIndexedOrNullSymbol),
                "kk_sequence_reduceIndexedOrNull"
            )
        }
    }

    func testListFlatMapRegistersRuntimeExternalLink() throws {
        let source = """
        fun render(values: List<String>) {
            val result: List<Int> = values.flatMap { listOf(it.length) }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("flatMap"),
            ]
            let symbols = sema.symbols.lookupAll(fqName: memberFQName)
            XCTAssertEqual(symbols.count, 1, "Expected one synthetic List.flatMap overload")

            let symbol = try XCTUnwrap(symbols.first)
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_list_flatMap")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                  let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
            else {
                return XCTFail("Expected List.flatMap to return List<R>")
            }
            XCTAssertEqual(ctx.interner.resolve(returnSymbol.name), "List")

            let transformType = try XCTUnwrap(signature.parameterTypes.first)
            guard case let .functionType(functionType) = sema.types.kind(of: transformType),
                  case let .classType(transformReturnClassType) = sema.types.kind(of: sema.types.makeNonNullable(functionType.returnType)),
                  let transformReturnSymbol = sema.symbols.symbol(transformReturnClassType.classSymbol)
            else {
                return XCTFail("Expected List.flatMap transform to return Collection<R>")
            }
            XCTAssertEqual(ctx.interner.resolve(transformReturnSymbol.name), "Collection")
        }
    }

    func testSequenceFlatMapIndexedRegistersIterableAndSequenceOverloads() throws {
        let source = """
        fun render(values: Sequence<Int>) {
            val iterableResult = values.flatMapIndexed { index, value -> listOf(index, value * 10) }
            val sequenceResult = values.flatMapIndexed { index, value -> sequenceOf(index + value, value * 100) }
            println(iterableResult.toList())
            println(sequenceResult.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("flatMapIndexed"),
            ]
            let symbols = sema.symbols.lookupAll(fqName: memberFQName)
            XCTAssertEqual(symbols.count, 2, "Expected Iterable and Sequence flatMapIndexed overloads")
            XCTAssertTrue(symbols.allSatisfy {
                sema.symbols.externalLinkName(for: $0) == "kk_sequence_flatMapIndexed"
            })

            let transformReturnTypeNames = symbols.compactMap { symbolID -> String? in
                guard let parameterType = sema.symbols.functionSignature(for: symbolID)?.parameterTypes.first,
                      case let .functionType(functionType) = sema.types.kind(of: parameterType),
                      case let .classType(returnClassType) = sema.types.kind(of: sema.types.makeNonNullable(functionType.returnType)),
                      let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
                else { return nil }
                return ctx.interner.resolve(returnSymbol.name)
            }
            XCTAssertTrue(transformReturnTypeNames.contains("Iterable"))
            XCTAssertTrue(transformReturnTypeNames.contains("Sequence"))
        }
    }

    func testSequenceShuffledUsesRuntimeExternalLinks() throws {
        let source = """
        import kotlin.random.Random

        fun render(values: Sequence<Int>) {
            values.shuffled()
            values.shuffled(Random)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("shuffled"),
            ]
            let externalLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                sema.symbols.externalLinkName(for: $0)
            })
            XCTAssertTrue(externalLinks.contains("kk_sequence_shuffled"))
            XCTAssertTrue(externalLinks.contains("kk_sequence_shuffled_random"))
        }
    }

    func testSequenceRequireNoNullsSyntheticStubHasRuntimeExternalLink() throws {
        let source = """
        fun render(values: Sequence<Int?>) {
            val result: Sequence<Int> = values.requireNoNulls()
            println(result.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("requireNoNulls"),
            ]
            XCTAssertTrue(sema.symbols.lookupAll(fqName: fqName).contains { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_sequence_requireNoNulls"
            })
        }
    }

    func testMutableListMutationMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.add(1)
            values.add(1, 0)
            values.addAll(listOf(2, 3))
            values.removeAll(listOf(4))
            values.retainAll(listOf(5))
            values.removeAt(0)
            values.removeFirst()
            values.removeFirstOrNull()
            values.removeLast()
            values.removeLastOrNull()
            values.clear()
            values.fill(9)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks: [(String, Int, String)] = [
                ("add", 1, "kk_mutable_list_add"),
                ("add", 2, "kk_mutable_list_add_at"),
                ("addAll", 1, "kk_mutable_list_addAll"),
                ("removeAll", 1, "kk_mutable_list_removeAll"),
                ("retainAll", 1, "kk_mutable_list_retainAll"),
                ("removeAt", 1, "kk_mutable_list_removeAt"),
                ("removeFirst", 0, "kk_mutable_list_removeFirst"),
                ("removeFirstOrNull", 0, "kk_mutable_list_removeFirstOrNull"),
                ("removeLast", 0, "kk_mutable_list_removeLast"),
                ("removeLastOrNull", 0, "kk_mutable_list_removeLastOrNull"),
                ("clear", 0, "kk_mutable_list_clear"),
                ("fill", 1, "kk_mutable_list_fill"),
            ]

            for (memberName, argumentCount, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, valueArgs, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && valueArgs.count == argumentCount
                }, "Expected member call to \(memberName) with \(argumentCount) arguments in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName)/\(argumentCount) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testMutableListBulkMutationFallbacksReturnBoolean() throws {
        let source = """
        fun mutate(): Boolean {
            val values = listOf(1, 2, 3).toMutableList()
            return values.addAll(listOf(4))
                || values.removeAll(listOf(5))
                || values.retainAll(listOf(1, 2))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("MutableList"),
                            ctx.interner.intern(memberName),
                        ]
                    ),
                    "Expected synthetic MutableList member \(memberName) to be registered"
                )

                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: symbolID),
                    "kk_mutable_list_\(memberName)",
                    "Expected \(memberName) to resolve to runtime extern"
                )
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    sema.types.booleanType,
                    "Expected \(memberName) to return Boolean"
                )
                XCTAssertFalse(
                    sema.bindings.isCollectionExpr(callExpr),
                    "Expected \(memberName) result to remain a scalar Boolean"
                )
            }
        }
    }

    func testMutableCollectionSequenceAddAllMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun appendCollection(collection: MutableCollection<Int>, source: Sequence<Int>) = collection.addAll(source)
        fun appendList(list: MutableList<Int>, source: Sequence<Int>) = list.addAll(source)
        fun appendSet(set: MutableSet<Int>, source: Sequence<Int>) = set.addAll(source)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedExternalLinks = [
                "collection": "kk_mutable_collection_addAll_sequence",
                "list": "kk_mutable_list_addAll_sequence",
                "set": "kk_mutable_set_addAll_sequence",
            ]

            for (receiverName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(receiver, callee, _, valueArgs, _) = expr,
                          ctx.interner.resolve(callee) == "addAll",
                          valueArgs.count == 1,
                          case let .nameRef(name, _) = ast.arena.expr(receiver)
                    else {
                        return false
                    }
                    return ctx.interner.resolve(name) == receiverName
                }, "Expected \(receiverName).addAll(source) call in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(receiverName).addAll(Sequence) to resolve to \(externalLinkName)"
                )
                XCTAssertEqual(sema.bindings.exprType(for: callExpr), sema.types.booleanType)
            }
        }
    }

    func testMutableListSortMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.sort()
            values.sortWith { a, b -> b - a }
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
                "sortWith": "kk_mutable_list_sortWith",
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

    func testListPrimitiveArrayConversionsUseRuntimeExternalLinks() throws {
        let cases: [SyntheticMemberCallCase] = [
            .init(
                source: """
                fun convert(values: List<Boolean>) {
                    values.toBooleanArray()
                }
                """,
                memberName: "toBooleanArray",
                expectedExternalLink: "kk_list_toBooleanArray",
                expectedTypeShape: .classNamed("BooleanArray")
            ),
            .init(
                source: """
                fun convert(values: List<Byte>) {
                    values.toByteArray()
                }
                """,
                memberName: "toByteArray",
                expectedExternalLink: "kk_list_toByteArray",
                expectedTypeShape: .classNamed("ByteArray")
            ),
            .init(
                source: """
                fun convert(values: List<Short>) {
                    values.toShortArray()
                }
                """,
                memberName: "toShortArray",
                expectedExternalLink: "kk_list_toShortArray",
                expectedTypeShape: .classNamed("ShortArray")
            ),
            .init(
                source: """
                fun convert(values: List<Int>) {
                    values.toIntArray()
                }
                """,
                memberName: "toIntArray",
                expectedExternalLink: "kk_list_toIntArray",
                expectedTypeShape: .classNamed("IntArray")
            ),
            .init(
                source: """
                fun convert(values: List<Double>) {
                    values.toDoubleArray()
                }
                """,
                memberName: "toDoubleArray",
                expectedExternalLink: "kk_list_toDoubleArray",
                expectedTypeShape: .classNamed("DoubleArray")
            ),
            .init(
                source: """
                fun convert(values: List<Float>) {
                    values.toFloatArray()
                }
                """,
                memberName: "toFloatArray",
                expectedExternalLink: "kk_list_toFloatArray",
                expectedTypeShape: .classNamed("FloatArray")
            ),
        ]

        for testCase in cases {
            try assertSyntheticMemberCall(testCase)
        }
    }

    func testMutableListBulkMutationMembersUseInvariantReceiverTypes() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let ownerFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: ownerFQName + [interner.intern(memberName)]))
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                guard case let .classType(receiverType) = sema.types.kind(of: try XCTUnwrap(signature.receiverType)) else {
                    return XCTFail("Expected \(memberName) to use MutableList receiver type")
                }
                guard case .invariant = try XCTUnwrap(receiverType.args.first) else {
                    return XCTFail("Expected \(memberName) receiver projection to remain invariant")
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

    func testMutableListBulkCollectionMembersKeepInvariantReceiverType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let mutableListFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(fqName: mutableListFQName + [ctx.interner.intern(memberName)]),
                    "Expected synthetic MutableList member \(memberName) to be registered"
                )
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                let receiverType = try XCTUnwrap(signature.receiverType)
                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                    return XCTFail("Expected \(memberName) receiver to be a class type")
                }
                guard case .invariant = try XCTUnwrap(receiverClassType.args.first) else {
                    return XCTFail(
                        "Expected \(memberName) receiver to keep invariant element type, got \(sema.types.renderType(receiverType))"
                    )
                }

                let parameterType = try XCTUnwrap(signature.parameterTypes.first)
                guard case let .classType(parameterClassType) = sema.types.kind(of: parameterType) else {
                    return XCTFail("Expected \(memberName) parameter to be a class type")
                }
                guard case .out = try XCTUnwrap(parameterClassType.args.first) else {
                    return XCTFail(
                        "Expected \(memberName) parameter to remain covariant Collection<out E>, got \(sema.types.renderType(parameterType))"
                    )
                }
            }
        }
    }

    func testOutProjectedMutableListBlocksBulkMutationMembers() throws {
        let source = """
        fun mutate(values: MutableList<out Number>) {
            values.addAll(listOf(1, 2))
            values.removeAll(listOf(3, 4))
            values.retainAll(listOf(5, 6))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-VAR-OUT" }
            XCTAssertEqual(diagnostics.count, 3, "Projected MutableList bulk writes should be rejected")
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
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

    func testMutableListBulkOperationsAcceptListArguments() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.addAll(listOf(1, 2))
            values.removeAll(listOf(1))
            values.retainAll(listOf(2))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    func testMutableListMatchesTransitiveCollectionConstraint() throws {
        let source = """
        fun <T> consume(values: Collection<T>): T? = values.firstOrNull()

        fun demo(values: MutableList<Int>): Int? = consume(values)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let consumeCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "consume"
            }, "Expected consume(values) call in AST")

            XCTAssertNotNil(
                sema.bindings.callBinding(for: consumeCall)?.chosenCallee,
                "Expected MutableList<Int> to satisfy Collection<T> through transitive lifting"
            )
        }
    }

    func testListIteratorMemberResolvesWithoutTypeConstraintFailure() throws {
        let source = """
        class IntContainer(private val elements: List<Int>) {
            operator fun iterator(): Iterator<Int> = elements.iterator()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let iteratorCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "iterator"
            }, "Expected List.iterator() call in AST")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: iteratorCall)?.chosenCallee,
                "Expected List.iterator() to resolve"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_range_iterator"
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

    func testListElementAtUsesRuntimeExternalLink() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            list.elementAt(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "elementAt"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "elementAt should resolve"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_list_elementAt"
            )
        }
    }

    func testListElementAtOrNullUsesRuntimeExternalLink() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            list.elementAtOrNull(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "elementAtOrNull"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "elementAtOrNull should resolve"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_list_elementAtOrNull"
            )
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

    func testSetRegistersCollectionAsNominalSupertype() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let setSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
            ]))
            let collectionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Collection"),
            ]))

            XCTAssertEqual(
                sema.types.directNominalSupertypes(for: setSymbol),
                [collectionSymbol],
                "Expected Set to register Collection as its nominal supertype"
            )
        }
    }

    func testContainsAllMembersUseCollectionRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let listContainsAll = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("containsAll"),
            ]))
            let setContainsAll = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
                ctx.interner.intern("containsAll"),
            ]))

            XCTAssertEqual(sema.symbols.externalLinkName(for: listContainsAll), "kk_list_containsAll")
            XCTAssertEqual(sema.symbols.externalLinkName(for: setContainsAll), "kk_set_containsAll")
        }
    }

    func testSetContainsAllUsesCollectionParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let setContainsAll = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
                ctx.interner.intern("containsAll"),
            ]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: setContainsAll))
            let parameterType = try XCTUnwrap(signature.parameterTypes.first)

            guard case let .classType(collectionType) = sema.types.kind(of: parameterType) else {
                return XCTFail("Set.containsAll should accept Collection<E>")
            }

            XCTAssertEqual(
                try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(collectionType.classSymbol)?.name)),
                "Collection"
            )
            guard case let .out(elementType) = try XCTUnwrap(collectionType.args.first) else {
                return XCTFail("Collection parameter should preserve the element projection")
            }
            let typeParamSymbol = try XCTUnwrap(signature.typeParameterSymbols.first)
            let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            XCTAssertEqual(elementType, expectedElementType)
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
            values.addAll(listOf(2, 3))
            values.addAll(setOf(2, 3))
            values.clear()
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
                "addAll": "kk_mutable_set_addAll",
                "clear": "kk_mutable_set_clear",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                if memberName == "addAll" {
                    let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("MutableSet"),
                        ctx.interner.intern(memberName),
                    ]))
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: symbol),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                } else {
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

            let addAllSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableSet"),
                ctx.interner.intern("addAll"),
            ]))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: addAllSymbol),
                "kk_mutable_set_addAll",
                "Expected addAll to resolve to kk_mutable_set_addAll"
            )
        }
    }

    func testMutableListBulkMutationMembersUseInvariantReceiverType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let mutableListFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: mutableListFQName + [ctx.interner.intern(memberName)]))
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
                let receiverType = try XCTUnwrap(signature.receiverType)

                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType),
                      let firstArg = receiverClassType.args.first
                else {
                    return XCTFail("Expected MutableList.\(memberName) receiver to be a class type")
                }

                guard case .invariant = firstArg else {
                    return XCTFail("Expected MutableList.\(memberName) receiver to remain invariant")
                }
            }
        }
    }

    func testMutableSetClearIsNotMarkedOperatorFunction() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let clearSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableSet"),
                ctx.interner.intern("clear"),
            ]))

            XCTAssertFalse(
                sema.symbols.symbol(clearSymbol)?.flags.contains(.operatorFunction) == true,
                "MutableSet.clear should not be registered as an operator function"
            )
        }
    }

    func testMutableSetAddAllUsesCollectionParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableSet"),
                interner.intern("addAll"),
            ]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            let parameterType = try XCTUnwrap(signature.parameterTypes.first)

            guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                return XCTFail("Expected MutableSet.addAll to take a collection type")
            }
            XCTAssertEqual(
                try interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)),
                "Collection"
            )
            guard case let .out(elementType) = try XCTUnwrap(classType.args.first),
                  case .typeParam = sema.types.kind(of: elementType)
            else {
                return XCTFail("Expected MutableSet.addAll parameter to use Collection<out E>")
            }
        }
    }

    func testMutableCollectionArrayAddAllOverloadsUseRuntimeExternalLinks() throws {
        let cases: [(String, String, String)] = [
            (
                "MutableCollection",
                "kk_mutable_collection_addAll",
                "fun mutate(values: MutableCollection<Int>) { values.addAll(arrayOf(1, 2)) }"
            ),
            (
                "MutableList",
                "kk_mutable_list_addAll",
                "fun mutate(values: MutableList<Int>) { values.addAll(arrayOf(1, 2)) }"
            ),
            (
                "MutableSet",
                "kk_mutable_set_addAll",
                "fun mutate(values: MutableSet<Int>) { values.addAll(arrayOf(1, 2)) }"
            ),
        ]

        for (receiverName, expectedExternalLink, source) in cases {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)

                let ast = try XCTUnwrap(ctx.ast)
                let sema = try XCTUnwrap(ctx.sema)
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "addAll"
                }, "Expected \(receiverName).addAll(Array) call in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)

                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedExternalLink,
                    "Expected \(receiverName).addAll(Array) to resolve to \(expectedExternalLink)"
                )

                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
                let parameterType = try XCTUnwrap(signature.parameterTypes.first)
                guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                    return XCTFail("Expected \(receiverName).addAll(Array) to take an Array parameter")
                }
                XCTAssertEqual(
                    try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)),
                    "Array"
                )
            }
        }
    }

    func testMutableCollectionIterableAddAllOverloadsUseRuntimeExternalLinks() throws {
        let cases: [(String, String, String)] = [
            (
                "MutableCollection",
                "kk_mutable_collection_addAll_iterable",
                "fun mutate(values: MutableCollection<Int>, source: Iterable<Int>) { values.addAll(source) }"
            ),
            (
                "MutableList",
                "kk_mutable_list_addAll_iterable",
                "fun mutate(values: MutableList<Int>, source: Iterable<Int>) { values.addAll(source) }"
            ),
            (
                "MutableList sequence as Iterable",
                "kk_mutable_list_addAll_iterable",
                "fun mutate(values: MutableList<Int>) { values.addAll(sequenceOf(1).asIterable()) }"
            ),
            (
                "MutableSet",
                "kk_mutable_set_addAll_iterable",
                "fun mutate(values: MutableSet<Int>, source: Iterable<Int>) { values.addAll(source) }"
            ),
        ]

        for (receiverName, expectedExternalLink, source) in cases {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)

                let ast = try XCTUnwrap(ctx.ast)
                let sema = try XCTUnwrap(ctx.sema)
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "addAll"
                }, "Expected \(receiverName).addAll(Iterable) call in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)

                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedExternalLink,
                    "Expected \(receiverName).addAll(Iterable) to resolve to \(expectedExternalLink)"
                )

                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
                let parameterType = try XCTUnwrap(signature.parameterTypes.first)
                guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                    return XCTFail("Expected \(receiverName).addAll(Iterable) to take an Iterable parameter")
                }
                XCTAssertEqual(
                    try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)),
                    "Iterable"
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
                (mapFQ, "containsValue", "kk_map_contains_value"),
                (mapFQ, "forEach", "kk_map_forEach"),
                (mapFQ, "map", "kk_map_map"),
                (mapFQ, "filter", "kk_map_filter"),
                (mapFQ, "filterNot", "kk_map_filterNot"),
                (mapFQ, "keys", "kk_map_keys"),
                (mapFQ, "values", "kk_map_values"),
                (mapFQ, "entries", "kk_map_entries"),
                (mapFQ, "mapValues", "kk_map_mapValues"),
                (mapFQ, "mapValuesTo", "kk_map_mapValuesTo"),
                (mapFQ, "mapKeys", "kk_map_mapKeys"),
                (mapFQ, "mapKeysTo", "kk_map_mapKeysTo"),
                (mapFQ, "filterKeys", "kk_map_filterKeys"),
                (mapFQ, "filterValues", "kk_map_filterValues"),
                (mapFQ, "getValue", "kk_map_getValue"),
                (mapFQ, "withDefault", "kk_map_withDefault"),
                (mapFQ, "toList", "kk_map_toList"),
                (mapFQ, "toMutableMap", "kk_map_to_mutable_map"),
                (mutableMapFQ, "put", "kk_mutable_map_put"),
                (mutableMapFQ, "remove", "kk_mutable_map_remove"),
                (mutableMapFQ, "putAll", "kk_mutable_map_putAll"),
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

    func testMapWithDefaultSurfaceResolvesDefaultLambda() throws {
        let source = """
        fun probe(values: Map<Int, Int>): Int {
            val defaults = values.withDefault { it * 10 }
            return defaults.getValue(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Map.withDefault surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
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

            for memberName in ["sumOf", "forEachIndexed", "mapIndexed", "filterIndexed"] {
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

    func testListFilterIndexedUsesRuntimeExternalLink() throws {
        let source = """
        fun main() {
            val list = listOf(10, 20, 30)
            list.filterIndexed { index, value -> index + value > 20 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIndexed"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "filterIndexed should resolve"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_list_filterIndexed"
            )
        }
    }

    func testListFilterIsInstanceUsesRuntimeExternalLink() throws {
        let source = """
        fun main() {
            val list: List<Any> = listOf(1, "two", 3)
            list.filterIsInstance<Int>()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIsInstance"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "filterIsInstance should resolve"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_list_filterIsInstance"
            )
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

            for memberName in ["forEach", "map", "filter", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo"] {
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

    func testMapEntryToPairSurfaceIsRegistered() throws {
        let source = """
        fun probe(values: Map<String, Int>): List<Pair<String, Int>> {
            return values.map { it.toPair() }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Map.Entry.toPair surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let entryFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Map"),
                ctx.interner.intern("Entry"),
            ]
            let toPairSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: entryFQName + [ctx.interner.intern("toPair")]),
                "Expected Map.Entry.toPair to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: toPairSymbol), "kk_map_entry_to_pair")
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toPairSymbol))
            guard case let .classType(pairType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected Map.Entry.toPair to return Pair<K, V>")
            }
            let pairName = try XCTUnwrap(sema.symbols.symbol(pairType.classSymbol)?.name)
            XCTAssertEqual(ctx.interner.resolve(pairName), "Pair")
            XCTAssertEqual(pairType.args.count, 2)
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

    func testMapKeysToResolvesWithMutableMapDestination() throws {
        let source = """
        fun remap(values: Map<Int, String>, destination: MutableMap<Int, String>): MutableMap<Int, String> {
            return values.mapKeysTo(destination) { entry -> entry.key + 10 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Map.mapKeysTo surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Map", "mapKeysTo"]
                .map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_map_mapKeysTo")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.parameterTypes.count, 2)
            XCTAssertEqual(signature.returnType, signature.parameterTypes[0])
        }
    }

    func testMapValuesToResolvesWithMutableMapDestination() throws {
        let source = """
        fun remap(values: Map<Int, String>, destination: MutableMap<Int, Int>): MutableMap<Int, Int> {
            return values.mapValuesTo(destination) { entry -> entry.value.length }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Map.mapValuesTo surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Map", "mapValuesTo"]
                .map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_map_mapValuesTo")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.parameterTypes.count, 2)
            XCTAssertEqual(signature.returnType, signature.parameterTypes[0])
        }
    }

    func testMutableMapPutAllUsesProjectedMapParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableMap"),
                interner.intern("putAll"),
            ]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            let parameterType = try XCTUnwrap(signature.parameterTypes.first)

            guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                return XCTFail("Expected MutableMap.putAll to take a map type")
            }
            XCTAssertEqual(
                try interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)),
                "Map"
            )
            guard classType.args.count == 2,
                  case let .out(keyType) = classType.args[0],
                  case let .out(valueType) = classType.args[1],
                  case .typeParam = sema.types.kind(of: keyType),
                  case .typeParam = sema.types.kind(of: valueType)
            else {
                return XCTFail("Expected MutableMap.putAll parameter to use projected Map<K, V>")
            }
        }
    }

    func testGroupingEachCountToUsesProjectedMutableMapParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Grouping"),
                interner.intern("eachCountTo"),
            ]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_grouping_eachCountTo")
            XCTAssertEqual(signature.parameterTypes.count, 1)
            XCTAssertEqual(signature.returnType, signature.parameterTypes[0])

            let receiverType = try XCTUnwrap(signature.receiverType)
            guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                return XCTFail("Expected Grouping.eachCountTo receiver to be a class type")
            }
            XCTAssertEqual(
                try interner.resolve(XCTUnwrap(sema.symbols.symbol(receiverClassType.classSymbol)?.name)),
                "Grouping"
            )

            let parameterType = try XCTUnwrap(signature.parameterTypes.first)
            guard case let .classType(parameterClassType) = sema.types.kind(of: parameterType) else {
                return XCTFail("Expected eachCountTo to take a MutableMap type")
            }
            XCTAssertEqual(
                try interner.resolve(XCTUnwrap(sema.symbols.symbol(parameterClassType.classSymbol)?.name)),
                "MutableMap"
            )
            XCTAssertEqual(parameterClassType.args.count, 2)
            guard case let .in(keyProjection) = parameterClassType.args[0],
                  case .typeParam = sema.types.kind(of: keyProjection),
                  case let .invariant(valueType) = parameterClassType.args[1]
            else {
                return XCTFail("Expected eachCountTo parameter to use MutableMap<in K, Int>")
            }
            XCTAssertEqual(valueType, sema.types.intType)
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

    func testListZipWithNextOverloadsInferReturnTypes() throws {
        let source = """
        fun pairs(values: List<Int>) = values.zipWithNext()
        fun gaps(values: List<Int>) = values.zipWithNext { left, right -> right - left }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected List.zipWithNext overloads to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            func projectedType(_ projection: TypeArg) -> TypeID? {
                switch projection {
                case let .invariant(type), let .out(type), let .in(type):
                    return type
                case .star:
                    return nil
                }
            }

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let noArgCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "zipWithNext" && args.isEmpty
            }, "Expected values.zipWithNext() call")
            let transformCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "zipWithNext" && args.count == 1
            }, "Expected values.zipWithNext { ... } call")

            let noArgType = try XCTUnwrap(sema.bindings.exprType(for: noArgCall))
            guard case let .classType(noArgListType) = sema.types.kind(of: noArgType),
                  let pairType = projectedType(try XCTUnwrap(noArgListType.args.first)),
                  case let .classType(pairClassType) = sema.types.kind(of: pairType)
            else {
                return XCTFail("Expected zipWithNext() to return List<Pair<Int, Int>>")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(noArgListType.classSymbol)?.name)), "List")
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(pairClassType.classSymbol)?.name)), "Pair")
            XCTAssertEqual(pairClassType.args.compactMap(projectedType), [sema.types.intType, sema.types.intType])

            let transformType = try XCTUnwrap(sema.bindings.exprType(for: transformCall))
            guard case let .classType(transformListType) = sema.types.kind(of: transformType),
                  let transformElementType = projectedType(try XCTUnwrap(transformListType.args.first))
            else {
                return XCTFail("Expected zipWithNext(transform) to return List<Int>")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(transformListType.classSymbol)?.name)), "List")
            XCTAssertEqual(transformElementType, sema.types.intType)
        }
    }

    func testListZipUsesRuntimeExternalLinkAndReturnsPairList() throws {
        let source = """
        fun zipValues(values: List<Int>, labels: List<String>) = values.zip(labels)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected List.zip to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "zip" && args.count == 1
            }, "Expected values.zip(labels) call in AST")

            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_list_zip")

            let callType = try XCTUnwrap(sema.bindings.exprType(for: callExpr))
            guard case let .classType(listType) = sema.types.kind(of: callType) else {
                return XCTFail("Expected List.zip to return a List type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(listType.classSymbol)?.name)), "List")
            let pairType: TypeID
            switch try XCTUnwrap(listType.args.first) {
            case let .invariant(type), let .out(type), let .in(type):
                pairType = type
            case .star:
                return XCTFail("Expected List.zip to return a concrete Pair projection")
            }
            guard case let .classType(pairClassType) = sema.types.kind(of: pairType) else {
                return XCTFail("Expected List.zip to return List<Pair<Int, String>>, got \(sema.types.kind(of: pairType))")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(pairClassType.classSymbol)?.name)), "Pair")
            XCTAssertEqual(pairClassType.args.count, 2)

            let firstArgument: TypeID
            switch pairClassType.args[0] {
            case let .invariant(type), let .out(type), let .in(type):
                firstArgument = type
            case .star:
                return XCTFail("Expected concrete Pair first argument")
            }
            let secondArgument: TypeID
            switch pairClassType.args[1] {
            case let .invariant(type), let .out(type), let .in(type):
                secondArgument = type
            case .star:
                return XCTFail("Expected concrete Pair second argument")
            }
            XCTAssertEqual(firstArgument, sema.types.intType)
            XCTAssertEqual(secondArgument, sema.types.stringType)
        }
    }

    func testStringAsIterableImplicitReceiverDoesNotExposeListOnlyMembers() throws {
        let source = """
        fun probe(): Char = with("hello") {
            asIterable().get(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }
}
