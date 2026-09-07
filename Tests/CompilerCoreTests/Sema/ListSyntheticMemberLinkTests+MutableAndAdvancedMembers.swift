#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Mutable-collection, Map, Build, Grouping, and zip/sort/conversion
/// test methods of `ListSyntheticMemberLinkTests`, split out to keep
/// each test source focused.
extension ListSyntheticMemberLinkTests {
    @Test
    func testListSortedAndSortedDescendingHaveComparableUpperBound() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let packageFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            let memberCases = ["sorted", "sortedDescending"]

            for memberName in memberCases {
                let allSymbols = sema.symbols.lookupAll(fqName: packageFQName + [ctx.interner.intern(memberName)])
                let symbolID = try #require(allSymbols.first { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                    else { return false }
                    return ctx.interner.resolve(receiverSymbol.name) == "List"
                        && ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_")
                })
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.typeParameterUpperBoundsList.count == 1)
                let upperBounds = signature.typeParameterUpperBoundsList[0]
                #expect(upperBounds.count == 1, "Expected Comparable upper bound for \(memberName) element type")

                guard case let .classType(boundType) = sema.types.kind(of: upperBounds[0]) else {
                    Issue.record("Expected \(memberName) upper bound to be a class type"); return
                }

                #expect(boundType.classSymbol == sema.types.comparableInterfaceSymbol)
                #expect(boundType.args.count == 1)

                guard case let .invariant(argumentType) = boundType.args[0] else {
                    Issue.record("Expected \(memberName) upper bound to reference invariant element type"); return
                }

                let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[0],
                    nullability: .nonNull
                )))
                #expect(argumentType == expectedElementType)
            }
        }
    }

    @Test
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
            #expect(boundDiagnostics.count == 2, "Expected bound diagnostics for sorted/sortedDescending")
        }
    }

    @Test
    func testListSortingAcceptsUserComparableElements() throws {
        let source = """
        class Version(val value: Int) : Comparable<Version> {
            override fun compareTo(other: Version): Int = value - other.value
        }

        fun render(values: List<Version>): List<Int> {
            return values.sorted().map { it.value }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected user-defined Comparable list sorting to type-check, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func testListConversionMembersResolveToBundledSource() throws {
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedExternalLinks: [String: String?] = [
                "toMutableList": nil,
                "toSet": nil,
                "joinToString": nil,
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                if memberName == "addAll" {
                    let symbol = try #require(sema.symbols.lookup(fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("MutableSet"),
                        ctx.interner.intern(memberName),
                    ]))
                    #expect(sema.symbols.externalLinkName(for: symbol) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                } else {
                    // Exclude bundled stdlib files to avoid matching internal calls
                    // like `result.add(element)` or `this.toMutableList()` inside
                    // bundled Iterable/Set HOFs.
                    let callExpr = try #require(firstExprID(in: ast) { id, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        guard ctx.interner.resolve(callee) == memberName else { return false }
                        if let range = ast.arena.exprRange(id),
                           ctx.sourceManager.origin(of: range.start.file)?.isBundledStdlib == true {
                            return false
                        }
                        return true
                    })
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                }
            }
        }
    }

    /// KSP-435: the generic Iterable/Collection conversions are bundled Kotlin
    /// source (Iterables.kt / Collections.kt), so they must resolve to a
    /// source-backed declaration without any `kk_*` external link.
    @Test
    func testCollectionAndIterableConversionMembersResolveToBundledSource() throws {
        let cases: [(source: String, memberName: String, resultClassName: String)] = [
            ("""
            fun copy(values: Collection<String>) {
                values.toList()
            }
            """, "toList", "List"),
            ("""
            fun copy(values: Collection<String>) {
                values.toMutableList()
            }
            """, "toMutableList", "MutableList"),
            ("""
            fun copy(values: Collection<String>) {
                values.toTypedArray()
            }
            """, "toTypedArray", "Array"),
            ("""
            fun copy(values: Iterable<String>) {
                values.toMutableList()
            }
            """, "toMutableList", "MutableList"),
            ("""
            fun copy(values: Iterable<String>) {
                values.toMutableSet()
            }
            """, "toMutableSet", "MutableSet"),
        ]

        for testCase in cases {
            try withTemporaryFile(contents: testCase.source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)

                let ast = try #require(ctx.ast)
                let sema = try #require(ctx.sema)
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == testCase.memberName
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(
                    sema.symbols.isSourceBackedSymbol(chosenCallee),
                    "\(testCase.memberName) must bind to the bundled Kotlin declaration"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "\(testCase.memberName) must not keep a kk_* external link"
                )
                try assertSyntheticMemberType(
                    try #require(sema.bindings.exprType(for: callExpr)),
                    matches: .classNamed(testCase.resultClassName),
                    sema: sema,
                    interner: ctx.interner,
                    memberName: testCase.memberName
                )
            }
        }
    }

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
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

            #expect(setResultTypes.keys.count == expectedMembers.count)

            for memberName in expectedMembers {
                let type = try #require(setResultTypes[memberName])
                guard case let .classType(classType) = sema.types.kind(of: type) else {
                    Issue.record("Expected \(memberName) to infer as Set<Int>, got \(sema.types.kind(of: type))"); return
                }
                #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Set")
                #expect(classType.args.count == 1, "Expected Set<Int> type argument for \(memberName)")
                let elementType: TypeID
                switch classType.args[0] {
                case let .invariant(type), let .out(type), let .in(type):
                    elementType = type
                case .star:
                    Issue.record("Expected concrete Set element projection for \(memberName)"); return
                }
                #expect(sema.types.kind(of: elementType) == .primitive(.int, .nonNull))
            }
        }
    }

    @Test
    func testListUnzipUsesRuntimeExternalLinkAndReturnsPairOfLists() throws {
        let source = """
        fun split(values: List<Pair<Int, String>>) {
            val result: Pair<List<Int>, List<String>> = values.unzip()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.unzip to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "unzip"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            // KSP-425: List.unzip() is now source-backed and has no external runtime link.
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected List.unzip to resolve to bundled source")

            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            guard case let .classType(pairType) = sema.types.kind(of: resultType) else {
                Issue.record("Expected List.unzip to return Pair<List<Int>, List<String>>"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(pairType.classSymbol)?.name)) == "Pair")
            #expect(pairType.args.count == 2)

            let firstListType = try projectedType(pairType.args[0])
            let secondListType = try projectedType(pairType.args[1])
            try assertListType(firstListType, elementType: sema.types.intType, sema: sema, interner: ctx.interner)
            try assertListType(secondListType, elementType: sema.types.stringType, sema: sema, interner: ctx.interner)
        }
    }

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                guard ctx.interner.resolve(callee) == "joinToString" else { return false }
                // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                // List<String>.joinToString(...) internally; exclude bundled
                // call sites so this finds the user's Sequence.joinToString(...).
                return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected Sequence.joinToString to have no bundled external link")
        }
    }

    @Test
    func testSequenceReduceIndexedOrNullIsSourceBacked() throws {
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "reduceIndexedOrNull"
            }, "Expected reduceIndexedOrNull member call")
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected reduceIndexedOrNull call to be bound"
            )
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
        }
    }

    @Test
    func testListFlatMapBindsToBundledSource() throws {
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

            let sema = try #require(ctx.sema)
            let sourceFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("flatMap"),
            ]
            let symbols = sema.symbols.lookupAll(fqName: sourceFQName)
            let listFlatMapSymbol = try #require(symbols.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      let (receiverClassType, _) = resolveClassTypeSymbol(receiverType, sema: sema),
                      let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol)
                else { return false }
                return ctx.interner.resolve(receiverSymbol.name) == "List"
            }, "Expected bundled source List.flatMap overload")

            let symbolInfo = try #require(sema.symbols.symbol(listFlatMapSymbol))
            #expect(!symbolInfo.flags.contains(.synthetic), "flatMap must be a bundled source declaration")
            #expect(sema.symbols.externalLinkName(for: listFlatMapSymbol) == nil, "source flatMap must not link to runtime")

            let symbol = listFlatMapSymbol
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                  let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
            else {
                Issue.record("Expected List.flatMap to return List<R>"); return
            }
            #expect(ctx.interner.resolve(returnSymbol.name) == "List")

            let transformType = try #require(signature.parameterTypes.first)
            guard case let .functionType(functionType) = sema.types.kind(of: transformType),
                  let (_, transformReturnSymbol) = resolveClassTypeSymbol(functionType.returnType, sema: sema)
            else {
                Issue.record("Expected List.flatMap transform to return List<R>"); return
            }
            #expect(ctx.interner.resolve(transformReturnSymbol.name) == "List")
        }
    }

    @Test
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

            let sema = try #require(ctx.sema)
            let packageFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("flatMapIndexed"),
            ]
            let sequenceFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
            ]
            guard let sequenceSymbol = sema.symbols.lookup(fqName: sequenceFQName) else {
                #expect(false, "Sequence symbol not found")
                return
            }
            let allSymbols = sema.symbols.lookupAll(fqName: packageFQName)
            let symbols = allSymbols.filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let (receiverClassType, _) = resolveClassTypeSymbol(signature.receiverType ?? sema.types.anyType, sema: sema)
                else { return false }
                return receiverClassType.classSymbol == sequenceSymbol
            }
            #expect(symbols.count == 2, "Expected Iterable and Sequence flatMapIndexed overloads")
            #expect(symbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil }, "Source-backed flatMapIndexed must not link to runtime")

            let transformReturnTypeNames = symbols.compactMap { symbolID -> String? in
                guard let parameterType = sema.symbols.functionSignature(for: symbolID)?.parameterTypes.first,
                      case let .functionType(functionType) = sema.types.kind(of: parameterType),
                      let (_, returnSymbol) = resolveClassTypeSymbol(functionType.returnType, sema: sema)
                else { return nil }
                return ctx.interner.resolve(returnSymbol.name)
            }
            #expect(transformReturnTypeNames.contains("Iterable"))
            #expect(transformReturnTypeNames.contains("Sequence"))
        }
    }

    @Test
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

            let sema = try #require(ctx.sema)
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("shuffled"),
            ]
            let externalLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                sema.symbols.externalLinkName(for: $0)
            })
            #expect(externalLinks.contains("kk_sequence_shuffled"))
            #expect(externalLinks.contains("kk_sequence_shuffled_random"))
        }
    }

    @Test
    func testSequenceRequireNoNullsIsBundledSourceWithNoRuntimeLink() throws {
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

            let sema = try #require(ctx.sema)
            let packageFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("requireNoNulls"),
            ]
            let sequenceFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
            ]
            guard let sequenceSymbol = sema.symbols.lookup(fqName: sequenceFQName) else {
                #expect(false, "Sequence symbol not found")
                return
            }
            let candidates = sema.symbols.lookupAll(fqName: packageFQName).filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let (receiverClassType, _) = resolveClassTypeSymbol(signature.receiverType ?? sema.types.anyType, sema: sema)
                else { return false }
                return receiverClassType.classSymbol == sequenceSymbol
            }
            #expect(candidates.isEmpty == false, "Expected a bundled source requireNoNulls")
            #expect(candidates.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil }, "Source-backed requireNoNulls must not have a runtime link")
        }
    }

    @Test
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
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedExternalLinks: [(String, Int, String)] = [
                ("add", 1, "__kk_mutable_list_add"),
                ("add", 2, "__kk_mutable_list_add_at"),
                ("addAll", 1, "__kk_mutable_list_addAll"),
                ("removeAll", 1, "__kk_mutable_list_removeAll"),
                ("retainAll", 1, "__kk_mutable_list_retainAll"),
                ("removeAt", 1, "__kk_mutable_list_removeAt"),
                ("clear", 0, "__kk_mutable_list_clear"),
            ]

            for (memberName, argumentCount, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, valueArgs, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && valueArgs.count == argumentCount
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName)/\(argumentCount) to resolve to \(externalLinkName)")
            }

            let sourceBackedMembers: [(String, Int)] = [
                ("removeFirst", 0),
                ("removeFirstOrNull", 0),
                ("removeLast", 0),
                ("removeLastOrNull", 0),
            ]
            for (memberName, argumentCount) in sourceBackedMembers {
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, valueArgs, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && valueArgs.count == argumentCount
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected \(memberName)/\(argumentCount) to remain source-backed")
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected \(memberName)/\(argumentCount) to resolve to bundled source")
            }
        }
    }

    /// KSP-436: predicate-driven mutable list operations are bundled Kotlin
    /// source; only the storage-mutating members keep a `__kk_mutable_*` bridge.
    @Test
    func testMutableListPredicateMembersResolveToBundledSource() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.removeIf { it > 1 }
            values.replaceAll { it + 1 }
            values.fill(9)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in ["removeIf", "replaceAll", "fill"] {
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, valueArgs, range) = expr,
                          valueArgs.count == 1,
                          !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                    else {
                        return false
                    }
                    return ctx.interner.resolve(callee) == memberName
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "Expected \(memberName) to be source-backed without a runtime link"
                )
                let declFile = try #require(sema.symbols.symbol(chosenCallee)?.declSite?.start.file)
                #expect(
                    ctx.sourceManager.path(of: declFile).hasPrefix("__bundled_"),
                    "Expected \(memberName) to resolve to a bundled stdlib declaration"
                )
            }
        }
    }

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                let symbolID = try #require(sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("MutableList"),
                            ctx.interner.intern(memberName),
                        ]
                    ))

                #expect(sema.symbols.externalLinkName(for: symbolID) == "__kk_mutable_list_\(memberName)", "Expected \(memberName) to resolve to runtime extern")
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.booleanType, "Expected \(memberName) to return Boolean")
                #expect(!(sema.bindings.isCollectionExpr(callExpr)), "Expected \(memberName) result to remain a scalar Boolean")
            }
        }
    }

    @Test
    func testMutableCollectionSequenceAddAllOverloadsResolveByReceiver() throws {
        let source = """
        fun appendCollection(collection: MutableCollection<Int>, source: Sequence<Int>) = collection.addAll(source)
        fun appendList(list: MutableList<Int>, source: Sequence<Int>) = list.addAll(source)
        fun appendSet(set: MutableSet<Int>, source: Sequence<Int>) = set.addAll(source)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedExternalLinks: [String: String?] = [
                // KSP-1019: MutableCollection uses the source-backed extension.
                "collection": nil,
                "list": "__kk_mutable_list_addAll_sequence",
                "set": "__kk_mutable_set_addAll_sequence",
            ]

            for (receiverName, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(receiver, callee, _, valueArgs, _) = expr,
                          ctx.interner.resolve(callee) == "addAll",
                          valueArgs.count == 1,
                          case let .nameRef(name, _) = ast.arena.expr(receiver)
                    else {
                        return false
                    }
                    return ctx.interner.resolve(name) == receiverName
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let expectedLinkDescription = externalLinkName ?? "source-backed extension"
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(receiverName).addAll(Sequence) to resolve to \(expectedLinkDescription)")
                if receiverName == "collection" {
                    #expect(sema.symbols.symbol(chosenCallee)?.declSite != nil, "Expected MutableCollection.addAll(Sequence) to be source-backed")
                }
                #expect(sema.bindings.exprType(for: callExpr) == sema.types.booleanType)
            }
        }
    }

    @Test
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
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
            let expectedExternalLinks: [String: String?] = [
                // KSP-426: MutableList sort methods are source-backed.
                "sort": nil,
                "sortWith": nil,
                "sortBy": nil,
                "sortByDescending": nil,
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                if let chosenCallee = sema.bindings.callBinding(for: callExpr)?.chosenCallee {
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) externalLinkName to be \(String(describing: externalLinkName))")
                }
            }
        }
    }

    @Test
    func testListPrimitiveArrayConversionsResolveToSourceBackedDeclarations() throws {
        let cases: [SyntheticMemberCallCase] = [
            .init(
                source: """
                fun convert(values: List<Boolean>) {
                    values.toBooleanArray()
                }
                """,
                memberName: "toBooleanArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("BooleanArray")
            ),
            .init(
                source: """
                fun convert(values: List<Byte>) {
                    values.toByteArray()
                }
                """,
                memberName: "toByteArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("ByteArray")
            ),
            .init(
                source: """
                fun convert(values: List<Short>) {
                    values.toShortArray()
                }
                """,
                memberName: "toShortArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("ShortArray")
            ),
            .init(
                source: """
                fun convert(values: List<Int>) {
                    values.toIntArray()
                }
                """,
                memberName: "toIntArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("IntArray")
            ),
            .init(
                source: """
                fun convert(values: List<Double>) {
                    values.toDoubleArray()
                }
                """,
                memberName: "toDoubleArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("DoubleArray")
            ),
            .init(
                source: """
                fun convert(values: List<Float>) {
                    values.toFloatArray()
                }
                """,
                memberName: "toFloatArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("FloatArray")
            ),
            .init(
                source: """
                fun convert(values: List<UByte>) {
                    values.toUByteArray()
                }
                """,
                memberName: "toUByteArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("UByteArray")
            ),
            .init(
                source: """
                fun convert(values: List<UShort>) {
                    values.toUShortArray()
                }
                """,
                memberName: "toUShortArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("UShortArray")
            ),
            .init(
                source: """
                fun convert(values: List<UInt>) {
                    values.toUIntArray()
                }
                """,
                memberName: "toUIntArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("UIntArray")
            ),
            .init(
                source: """
                fun convert(values: List<ULong>) {
                    values.toULongArray()
                }
                """,
                memberName: "toULongArray",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("ULongArray")
            ),
        ]

        for testCase in cases {
            try assertSyntheticMemberCall(testCase)
        }
    }

    @Test
    func testMutableListBulkMutationMembersUseInvariantReceiverTypes() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let ownerFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbolID = try #require(sema.symbols.lookup(fqName: ownerFQName + [interner.intern(memberName)]))
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                guard case let .classType(receiverType) = sema.types.kind(of: try #require(signature.receiverType)) else {
                    Issue.record("Expected \(memberName) to use MutableList receiver type"); return
                }
                guard case .invariant = try #require(receiverType.args.first) else {
                    Issue.record("Expected \(memberName) receiver projection to remain invariant"); return
                }
            }
        }
    }

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: path))

            let expectedExternalLinks = [
                "addAll": "__kk_mutable_list_addAll",
                "removeAll": "__kk_mutable_list_removeAll",
                "retainAll": "__kk_mutable_list_retainAll",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else {
                        return false
                    }
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
            }
        }
    }

    @Test
    func testMutableListBulkCollectionMembersKeepInvariantReceiverType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let mutableListFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbolID = try #require(sema.symbols.lookup(fqName: mutableListFQName + [ctx.interner.intern(memberName)]))
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                let receiverType = try #require(signature.receiverType)
                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                    Issue.record("Expected \(memberName) receiver to be a class type"); return
                }
                guard case .invariant = try #require(receiverClassType.args.first) else {
                    Issue.record("Expected \(memberName) receiver to keep invariant element type, got \(sema.types.renderType(receiverType))"); return
                }

                let parameterType = try #require(signature.parameterTypes.first)
                guard case let .classType(parameterClassType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected \(memberName) parameter to be a class type"); return
                }
                guard case .out = try #require(parameterClassType.args.first) else {
                    Issue.record("Expected \(memberName) parameter to remain covariant Collection<out E>, got \(sema.types.renderType(parameterType))"); return
                }
            }
        }
    }

    @Test
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
            #expect(diagnostics.count == 3, "Projected MutableList bulk writes should be rejected")
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in ["sort", "sortBy", "sortByDescending"] {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil, "Expected immutable List.\(memberName) to remain unresolved")
            }

            #expect(!(ctx.diagnostics.diagnostics.isEmpty), "Expected diagnostics for immutable List.sort* calls")
        }
    }

    @Test
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

    @Test
    func testMutableListMatchesTransitiveCollectionConstraint() throws {
        let source = """
        fun <T> consume(values: Collection<T>): T? = values.firstOrNull()

        fun demo(values: MutableList<Int>): Int? = consume(values)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let consumeCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "consume"
            })

            #expect(sema.bindings.callBinding(for: consumeCall)?.chosenCallee != nil, "Expected MutableList<Int> to satisfy Collection<T> through transitive lifting")
        }
    }

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let iteratorCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "iterator"
            })

            let chosenCallee = try #require(sema.bindings.callBinding(for: iteratorCall)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_iterator")
        }
    }

    /// Regression: listOf(...).contains/isEmpty must not emit KSWIFTK-SEMA-VAR-OUT.
    /// The synthetic List type uses .out projection; variance relaxation must apply.
    @Test
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
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            var containsCalls: [ExprID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, range) = expr,
                      ctx.interner.resolve(callee) == "contains",
                      !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                else { continue }
                containsCalls.append(exprID)
            }
            #expect(containsCalls.count == 2)
            for callID in containsCalls {
                let binding = sema.bindings.callBinding(for: callID)
                #expect(binding?.chosenCallee != nil, "contains should resolve")
                if let chosen = binding?.chosenCallee {
                    #expect(sema.symbols.externalLinkName(for: chosen) == nil, "List.contains is source-backed and should have no external link")
                }
            }
        }
    }

    @Test
    func testListElementAtUsesBundledSourceFunction() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            list.elementAt(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "elementAt"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosenCallee))
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(ctx.interner.resolve(symbol.name) == "elementAt")
        }
    }

    @Test
    func testListElementAtOrNullUsesBundledSourceFunction() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            list.elementAtOrNull(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "elementAtOrNull"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosenCallee))
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(ctx.interner.resolve(symbol.name) == "elementAtOrNull")
        }
    }

    @Test
    func testSetMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun check(values: Set<Int>) {
            values.contains(42)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { id, expr in
                guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                guard ctx.interner.resolve(callee) == "contains" else { return false }
                guard !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_") else { return false }
                return true
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "__kk_set_contains", "Expected contains to resolve to __kk_set_contains")
        }
    }

    @Test
    func testSetFilterUsesSetSpecificBundledSourceFunction() throws {
        let source = """
        fun filterValues(values: Set<Int>): List<Int> {
            return values.filter { value -> value > 1 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected Set.filter to resolve cleanly: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                return ctx.interner.resolve(callee) == "filter"
                    && !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let chosenSymbol = try #require(sema.symbols.symbol(chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            let receiverType = try #require(signature.receiverType)
            let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiverType, sema: sema))

            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(chosenSymbol.fqName == [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("filter"),
            ])
            #expect(receiverSymbol.fqName == [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
            ])
        }
    }

    @Test
    func testSetRegistersCollectionAsNominalSupertype() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let setSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
            ]))
            let collectionSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Collection"),
            ]))

            #expect(sema.types.directNominalSupertypes(for: setSymbol) == [collectionSymbol], "Expected Set to register Collection as its nominal supertype")
        }
    }

    @Test
    func testContainsAllMembersUseCollectionRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            let listSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("List")]))
            let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")]))

            func containsAllSymbol(owner: SymbolID) -> SymbolID? {
                let name = ctx.interner.intern("containsAll")
                func matches(_ symbolID: SymbolID) -> Bool {
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: receiverType)
                    else {
                        return false
                    }
                    return classType.classSymbol == owner
                }
                if let sourceBacked = sema.symbols.lookupAll(fqName: collectionsPkg + [name]).first(where: matches) {
                    return sourceBacked
                }
                guard let ownerSymbol = sema.symbols.symbol(owner) else { return nil }
                return sema.symbols.lookupAll(fqName: ownerSymbol.fqName + [name]).first(where: matches)
            }

            let listContainsAll = try #require(containsAllSymbol(owner: listSymbol), "Expected List.containsAll source extension")
            let setContainsAll = try #require(containsAllSymbol(owner: setSymbol), "Expected Set.containsAll")

            // List.containsAll is source-backed (KSP-423), Set.containsAll (KSP-432).
            #expect(sema.symbols.externalLinkName(for: listContainsAll) == nil)
            #expect(sema.symbols.externalLinkName(for: setContainsAll) == nil)
        }
    }

    @Test
    func testSetContainsAllUsesCollectionParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")]))
            let setContainsAll = try #require(
                sema.symbols.lookupAll(fqName: collectionsPkg + [ctx.interner.intern("containsAll")]).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: receiverType)
                    else {
                        return false
                    }
                    return classType.classSymbol == setSymbol
                },
                "Expected Set.containsAll source extension"
            )
            let signature = try #require(sema.symbols.functionSignature(for: setContainsAll))
            let parameterType = try #require(signature.parameterTypes.first)

            guard case let .classType(collectionType) = sema.types.kind(of: parameterType) else {
                Issue.record("Set.containsAll should accept Collection<E>"); return
            }

            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(collectionType.classSymbol)?.name)) == "Collection")
            guard case let .out(elementType) = try #require(collectionType.args.first) else {
                Issue.record("Collection parameter should preserve the element projection"); return
            }
            let typeParamSymbol = try #require(signature.typeParameterSymbols.first)
            let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            #expect(elementType == expectedElementType)
        }
    }

    @Test
    func testContainsMembersAreMarkedOperatorFunctions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            let listSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("List")]))
            let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")]))

            func containsSymbol(owner: SymbolID, packageFQName: [InternedString]) -> SymbolID? {
                let name = ctx.interner.intern("contains")
                func matches(_ symbolID: SymbolID) -> Bool {
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: receiverType)
                    else {
                        return false
                    }
                    return classType.classSymbol == owner
                }
                if let sourceBacked = sema.symbols.lookupAll(fqName: packageFQName + [name]).first(where: matches) {
                    return sourceBacked
                }
                guard let ownerSymbol = sema.symbols.symbol(owner) else { return nil }
                return sema.symbols.lookupAll(fqName: ownerSymbol.fqName + [name]).first(where: matches)
            }

            let listContains = try #require(containsSymbol(owner: listSymbol, packageFQName: collectionsPkg))
            let setContains = try #require(containsSymbol(owner: setSymbol, packageFQName: collectionsPkg))
            #expect(sema.symbols.symbol(listContains)?.flags.contains(.operatorFunction) == true)
            #expect(sema.symbols.symbol(setContains)?.flags.contains(.operatorFunction) == true)

            // KSP-408: `kotlin.text.contains` now has multiple overloads under the same
            // fqName: CharSequence.contains(other: CharSequence) (1-arg `operator fun`
            // used for `in` resolution), CharSequence.contains(other, ignoreCase) (2-arg,
            // not an operator function), and the pre-existing String.contains(regex:
            // Regex) synthetic stub (1-arg, but a different receiver type and not marked
            // as an operator function). Disambiguate by receiver type rather than relying
            // on `lookup`/arity alone, mirroring the List/Set `containsSymbol` helper above.
            let charSequenceSymbol = try #require(sema.types.charSequenceInterfaceSymbol)
            let stringContainsCandidates = sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("text"),
                ctx.interner.intern("contains"),
            ])
            let stringContains = try #require(stringContainsCandidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      case let .classType(classType) = sema.types.kind(of: receiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol && signature.parameterTypes.count == 1
            })
            #expect(sema.symbols.symbol(stringContains)?.flags.contains(.operatorFunction) == true)
        }
    }

    @Test
    func testWithIndexUsesIterableOfIndexedValueSignature() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let withIndexSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("withIndex"),
            ]))
            let indexedValueSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("IndexedValue"),
            ]))
            let indexedValueRecord = try #require(sema.symbols.symbol(indexedValueSymbol))
            #expect(indexedValueRecord.kind == .class)
            #expect(indexedValueRecord.flags.contains(.dataType))

            let signature = try #require(sema.symbols.functionSignature(for: withIndexSymbol))
            guard case let .classType(iterableType) = sema.types.kind(of: signature.returnType),
                  let firstArg = iterableType.args.first
            else {
                Issue.record("Expected withIndex() to return Iterable<IndexedValue<T>>"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(iterableType.classSymbol)?.name)) == "Iterable")
            let elementType: TypeID
            switch firstArg {
            case .invariant(let t), .out(let t), .in(let t):
                elementType = t
            case .star:
                Issue.record("Expected Iterable element type, got star projection"); return
            }
            guard case let .classType(indexedValueType) = sema.types.kind(of: elementType) else {
                Issue.record("Expected Iterable element type to be IndexedValue"); return
            }
            #expect(indexedValueType.classSymbol == indexedValueSymbol)
        }
    }

    @Test
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

            let sema = try #require(ctx.sema)

            let expectedExternalLinks = [
                "add": "__kk_mutable_set_add",
                "remove": "__kk_mutable_set_remove",
                "addAll": "__kk_mutable_set_addAll",
                "clear": "__kk_mutable_set_clear",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let symbol = try #require(sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern("MutableSet"),
                    ctx.interner.intern(memberName),
                ]))
                #expect(sema.symbols.externalLinkName(for: symbol) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
            }

            let addAllSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableSet"),
                ctx.interner.intern("addAll"),
            ]))
            #expect(sema.symbols.externalLinkName(for: addAllSymbol) == "__kk_mutable_set_addAll", "Expected addAll to resolve to kk_mutable_set_addAll")
        }
    }

    @Test
    func testMutableListBulkMutationMembersUseInvariantReceiverType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let mutableListFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbol = try #require(sema.symbols.lookup(fqName: mutableListFQName + [ctx.interner.intern(memberName)]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                let receiverType = try #require(signature.receiverType)

                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType),
                      let firstArg = receiverClassType.args.first
                else {
                    Issue.record("Expected MutableList.\(memberName) receiver to be a class type"); return
                }

                guard case .invariant = firstArg else {
                    Issue.record("Expected MutableList.\(memberName) receiver to remain invariant"); return
                }
            }
        }
    }

    @Test
    func testMutableSetClearIsNotMarkedOperatorFunction() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let clearSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableSet"),
                ctx.interner.intern("clear"),
            ]))

            #expect(!(sema.symbols.symbol(clearSymbol)?.flags.contains(.operatorFunction) == true), "MutableSet.clear should not be registered as an operator function")
        }
    }

    @Test
    func testMutableSetAddAllUsesCollectionParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let symbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableSet"),
                interner.intern("addAll"),
            ]))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            let parameterType = try #require(signature.parameterTypes.first)

            guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                Issue.record("Expected MutableSet.addAll to take a collection type"); return
            }
            #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Collection")
            guard case let .out(elementType) = try #require(classType.args.first),
                  case .typeParam = sema.types.kind(of: elementType)
            else {
                Issue.record("Expected MutableSet.addAll parameter to use Collection<out E>"); return
            }
        }
    }

    @Test
    func testMutableCollectionArrayAddAllOverloadsResolveByReceiver() throws {
        let cases: [(String, String?, String)] = [
            (
                "MutableCollection",
                nil,
                "fun mutate(values: MutableCollection<Int>) { values.addAll(arrayOf(1, 2)) }"
            ),
            (
                "MutableList",
                "__kk_mutable_list_addAll",
                "fun mutate(values: MutableList<Int>) { values.addAll(arrayOf(1, 2)) }"
            ),
            (
                "MutableSet",
                "__kk_mutable_set_addAll",
                "fun mutate(values: MutableSet<Int>) { values.addAll(arrayOf(1, 2)) }"
            ),
        ]

        for (receiverName, expectedExternalLink, source) in cases {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)

                let ast = try #require(ctx.ast)
                let sema = try #require(ctx.sema)
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                    guard ctx.interner.resolve(callee) == "addAll" else { return false }
                    // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                    // MutableList<String>.addAll(...) internally; exclude
                    // bundled call sites so this finds the user's call.
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)

                let expectedLinkDescription = expectedExternalLink ?? "source-backed extension"
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedExternalLink, "Expected \(receiverName).addAll(Array) to resolve to \(expectedLinkDescription)")
                if receiverName == "MutableCollection" {
                    #expect(sema.symbols.symbol(chosenCallee)?.declSite != nil, "Expected MutableCollection.addAll(Array) to be source-backed")
                }

                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let parameterType = try #require(signature.parameterTypes.first)
                guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected \(receiverName).addAll(Array) to take an Array parameter"); return
                }
                #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Array")
            }
        }
    }

    @Test
    func testMutableCollectionIterableAddAllOverloadsResolveByReceiver() throws {
        let cases: [(String, String?, String)] = [
            (
                "MutableCollection",
                nil,
                "fun mutate(values: MutableCollection<Int>, source: Iterable<Int>) { values.addAll(source) }"
            ),
            (
                "MutableList",
                "__kk_mutable_list_addAll_iterable",
                "fun mutate(values: MutableList<Int>, source: Iterable<Int>) { values.addAll(source) }"
            ),
            (
                "MutableList sequence as Iterable",
                "__kk_mutable_list_addAll_iterable",
                "fun mutate(values: MutableList<Int>) { values.addAll(sequenceOf(1).asIterable()) }"
            ),
            (
                "MutableSet",
                "__kk_mutable_set_addAll_iterable",
                "fun mutate(values: MutableSet<Int>, source: Iterable<Int>) { values.addAll(source) }"
            ),
        ]

        for (receiverName, expectedExternalLink, source) in cases {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)

                let ast = try #require(ctx.ast)
                let sema = try #require(ctx.sema)
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                    guard ctx.interner.resolve(callee) == "addAll" else { return false }
                    // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                    // MutableList<String>.addAll(...) internally; exclude
                    // bundled call sites so this finds the user's call.
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)

                let expectedLinkDescription = expectedExternalLink ?? "source-backed extension"
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedExternalLink, "Expected \(receiverName).addAll(Iterable) to resolve to \(expectedLinkDescription)")
                if receiverName == "MutableCollection" {
                    #expect(sema.symbols.symbol(chosenCallee)?.declSite != nil, "Expected MutableCollection.addAll(Iterable) to be source-backed")
                }

                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let parameterType = try #require(signature.parameterTypes.first)
                guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected \(receiverName).addAll(Iterable) to take an Iterable parameter"); return
                }
                #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Iterable")
            }
        }
    }

    /// Map member calls (containsKey, put, remove) go through the collection-fallback
    /// inference path which does not record a callBinding. Instead we verify that the
    /// synthetic symbols in the symbol table carry the correct external link names.
    @Test
    func testMapSyntheticSymbolsHaveCorrectExternalLinkNames() throws {
        let source = """
        fun noop() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let kotlinCollections = ["kotlin", "collections"].map { interner.intern($0) }
            let mutableMapFQ = kotlinCollections + [interner.intern("MutableMap")]

            // KSP-430 / KSP-431: Map higher-order functions (MapHOF.kt) and Map
            // lookup/conversion members (MapLookupAndTransform.kt) are
            // source-backed, so only non-migrated Map members appear here.
            let expectedLinks: [(fqName: [InternedString], memberName: String, externalLink: String)] = [
                (mutableMapFQ, "put", "__kk_mutable_map_put"),
                (mutableMapFQ, "remove", "__kk_mutable_map_remove"),
                (mutableMapFQ, "putAll", "__kk_mutable_map_putAll"),
            ]

            for (ownerFQ, memberName, expectedExternal) in expectedLinks {
                let memberFQ = ownerFQ + [interner.intern(memberName)]
                let symbolID = try #require(sema.symbols.lookup(fqName: memberFQ))
                #expect(sema.symbols.externalLinkName(for: symbolID) == expectedExternal, "Expected \(memberName) to have external link \(expectedExternal)")
            }
        }
    }

    @Test
    func testMapCountOverloadsAreBundledSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let packageFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
            ]
            let mapFQName = packageFQName + [interner.intern("Map")]

            func bundledMapCountSymbols(arity: Int) -> [SymbolID] {
                sema.symbols.lookupAll(fqName: packageFQName + [interner.intern("count")]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.count == arity,
                          let receiverType = signature.receiverType,
                          case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                          sema.symbols.symbol(receiverClassType.classSymbol)?.fqName == mapFQName
                    else {
                        return false
                    }
                    return ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_")
                }
            }

            let noArg = bundledMapCountSymbols(arity: 0)
            #expect(!noArg.isEmpty, "Expected bundled Kotlin source for Map.count()")
            #expect(noArg.allSatisfy { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                return symbol.flags.contains(.inlineFunction)
                    && sema.symbols.externalLinkName(for: symbolID) == nil
            })

            let predicate = bundledMapCountSymbols(arity: 1)
            #expect(!predicate.isEmpty, "Expected bundled Kotlin source for Map.count(predicate)")
            #expect(predicate.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })

            let syntheticNoArg = sema.symbols.lookupAll(fqName: mapFQName + [interner.intern("count")]).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.flags.contains(.synthetic),
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.parameterTypes.isEmpty
            }
            #expect(syntheticNoArg.isEmpty, "Map.count() must not retain a synthetic kk_map_size overload")
        }
    }

    @Test
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

            #expect(!(ctx.diagnostics.hasError), "Expected Map.withDefault surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testIndexedIterableMembersAreSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let packageFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]

            // KSP-626: forEachIndexed and withIndex are bundled Kotlin source.
            for memberName in ["forEachIndexed", "withIndex"] {
                let symbolID = try #require(sema.symbols.lookup(fqName: packageFQName + [ctx.interner.intern(memberName)]))
                let flags = try #require(sema.symbols.symbol(symbolID)?.flags)
                #expect(!flags.contains(.synthetic), "Expected \(memberName) to be source-backed")
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected \(memberName) to have no external link")
            }
        }
    }

    @Test
    func testListFilterIndexedUsesBundledSource() throws {
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

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIndexed"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.symbols.symbol(chosenCallee)?.fqName == [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("filterIndexed"),
            ])
        }
    }

    @Test
    func testListFilterIsInstanceUsesBundledSource() throws {
        let source = """
        fun main() {
            val list: List<Any> = listOf(1, "two", 3)
            list.filterIsInstance<Int>()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIsInstance"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.symbols.symbol(chosenCallee)?.fqName == [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("filterIsInstance"),
            ])
        }
    }

    @Test
    func testListFilterHOFsUseBundledSourceCalls() throws {
        let source = """
        fun main() {
            val values = listOf(10, 20, 30)
            val nullable: List<Int?> = listOf(1, null, 3)
            val mixed: List<Any> = listOf(1, "two", 3)
            values.filter { value -> value > 10 }
            values.filterNot { value -> value == 20 }
            nullable.filterNotNull()
            values.filterIndexed { index, value -> index + value > 20 }
            mixed.filterIsInstance<Int>()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            for name in ["filter", "filterNot", "filterNotNull", "filterIndexed", "filterIsInstance"] {
                let callExpr = try #require(memberCallExprIDs(named: name, in: ast, interner: ctx.interner).last)
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(sema.symbols.symbol(chosenCallee)?.fqName == [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern(name),
                ])
            }
        }
    }

    @Test
    func testMapHigherOrderMembersAreInlineAndToListPreservesPairType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let packageFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
            ]
            let mapFQName = packageFQName + [interner.intern("Map")]

            func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                case let .classType(classType):
                    return sema.symbols.symbol(classType.classSymbol)?.fqName
                default:
                    return nil
                }
            }

            for memberName in ["forEach", "map", "filter", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo"] {
                let candidates = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern(memberName)]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          nominalOwnerFQName(for: receiverType) == mapFQName
                    else {
                        return false
                    }
                    return true
                }
                let symbolID = try #require(candidates.first, "Expected bundled source for Map.\(memberName)")
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.flags.contains(.inlineFunction), "Expected \(memberName) to be inline")
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
                #expect(symbol.fqName == packageFQName + [interner.intern(memberName)])
            }

            // KSP-431: Map.toList is a bundled source extension, not a Map member stub.
            let toListSymbol = try #require(
                sema.symbols.lookupAll(fqName: packageFQName + [interner.intern("toList")]).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType
                    else {
                        return false
                    }
                    return nominalOwnerFQName(for: receiverType) == mapFQName
                },
                "Expected bundled source for Map.toList"
            )
            #expect(sema.symbols.externalLinkName(for: toListSymbol) == nil)
            let toListSignature = try #require(sema.symbols.functionSignature(for: toListSymbol))
            guard case let .classType(listType) = sema.types.kind(of: toListSignature.returnType) else {
                Issue.record("Expected Map.toList to return List<Pair<K, V>>"); return
            }
            let listName = try #require(sema.symbols.symbol(listType.classSymbol)?.name)
            #expect(interner.resolve(listName) == "List")
            let firstListArg = try #require(listType.args.first)
            let pairTypeID: TypeID
            switch firstListArg {
            case let .invariant(id), let .out(id), let .in(id):
                pairTypeID = id
            case .star:
                Issue.record("Expected Map.toList element type to be Pair"); return
            }
            guard case let .classType(pairType) = sema.types.kind(of: pairTypeID) else {
                Issue.record("Expected Map.toList element type to be Pair"); return
            }
            let pairName = try #require(sema.symbols.symbol(pairType.classSymbol)?.name)
            #expect(interner.resolve(pairName) == "Pair")
        }
    }

    @Test
    func testMapEntryToPairSurfaceIsRegistered() throws {
        let source = """
        fun probe(values: Map<String, Int>): Pair<String, Int> {
            val entry = values.entries.first()
            val key = entry.component1()
            val value = entry.component2()
            return entry.toPair()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected Map.Entry source-backed surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let packageFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            let entryFQName: [InternedString] = [
                packageFQName[0],
                packageFQName[1],
                ctx.interner.intern("Map"),
                ctx.interner.intern("Entry"),
            ]

            for memberName in ["component1", "component2", "toPair"] {
                let callExpr = try #require(firstExprID(in: ast) { exprID, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr,
                          ctx.interner.resolve(callee) == memberName,
                          let range = ast.arena.exprRange(exprID)
                    else {
                        return false
                    }
                    return ctx.sourceManager.origin(of: range.start.file)?.isBundledStdlib != true
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(
                    sema.symbols.isSourceBackedSymbol(chosenCallee),
                    "Map.Entry.\(memberName) must bind to bundled Kotlin source"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "Map.Entry.\(memberName) must not use a direct runtime link"
                )
                #expect(
                    sema.symbols.symbol(chosenCallee)?.fqName == packageFQName + [ctx.interner.intern(memberName)],
                    "Map.Entry.\(memberName) must resolve to the package-level source extension"
                )
            }

            for memberName in ["component1", "component2", "toPair"] {
                #expect(
                    sema.symbols.lookup(fqName: entryFQName + [ctx.interner.intern(memberName)]) == nil,
                    "Map.Entry.\(memberName) must not leave a synthetic nested alias"
                )
            }
        }
    }

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildListCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildList"
            })
            let buildListType = try #require(sema.bindings.exprType(for: buildListCall))
            guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                Issue.record("Expected buildList(...) to produce a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
            guard case let .out(elementType) = try #require(listType.args.first) else {
                Issue.record("Expected List element type argument"); return
            }
            #expect(elementType == sema.types.intType)

            // Use lastExprID to skip bundled stdlib's thisRef expressions
            let explicitThis = try #require(lastExprID(in: ast) { _, expr in
                if case .thisRef = expr { return true }
                return false
            })
            let explicitThisType = try #require(sema.bindings.exprType(for: explicitThis))
            guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                Issue.record("Expected builder receiver to be a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(receiverType.classSymbol)?.name)) == "MutableList")
            guard case let .invariant(receiverElementType) = try #require(receiverType.args.first) else {
                Issue.record("Expected MutableList element type argument"); return
            }
            #expect(receiverElementType == sema.types.intType)
        }
    }

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildMapCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildMap"
            })
            let buildMapType = try #require(sema.bindings.exprType(for: buildMapCall))
            guard case let .classType(mapType) = sema.types.kind(of: buildMapType) else {
                Issue.record("Expected buildMap(...) to produce a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(mapType.classSymbol)?.name)) == "Map")
            guard mapType.args.count >= 2,
                  case let .out(keyType) = mapType.args[0],
                  case let .out(valueType) = mapType.args[1]
            else {
                Issue.record("Expected Map key/value type arguments"); return
            }
            #expect(keyType == sema.types.stringType)
            #expect(valueType == sema.types.intType)

            // Use lastExprID to skip bundled stdlib's thisRef expressions
            let explicitThis = try #require(lastExprID(in: ast) { _, expr in
                if case .thisRef = expr { return true }
                return false
            })
            let explicitThisType = try #require(sema.bindings.exprType(for: explicitThis))
            guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                Issue.record("Expected builder receiver to be a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(receiverType.classSymbol)?.name)) == "MutableMap")
            guard receiverType.args.count >= 2,
                  case let .invariant(receiverKeyType) = receiverType.args[0],
                  case let .invariant(receiverValueType) = receiverType.args[1]
            else {
                Issue.record("Expected MutableMap key/value type arguments"); return
            }
            #expect(receiverKeyType == sema.types.stringType)
            #expect(receiverValueType == sema.types.intType)
        }
    }

    @Test
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
            #expect(!(ctx.diagnostics.hasError), "Expected Map.mapKeysTo surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let packageFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
            ]
            let mapFQName = packageFQName + [interner.intern("Map")]

            func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                case let .classType(classType):
                    return sema.symbols.symbol(classType.classSymbol)?.fqName
                default:
                    return nil
                }
            }

            let candidates = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern("mapKeysTo")]).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      nominalOwnerFQName(for: receiverType) == mapFQName
                else {
                    return false
                }
                return true
            }
            let symbol = try #require(candidates.first, "Expected bundled source for Map.mapKeysTo")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
            #expect(sema.symbols.symbol(symbol)?.fqName == packageFQName + [interner.intern("mapKeysTo")])

            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.parameterTypes.count == 2)
            #expect(signature.returnType == signature.parameterTypes[0])
        }
    }

    @Test
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
            #expect(!(ctx.diagnostics.hasError), "Expected Map.mapValuesTo surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let packageFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
            ]
            let mapFQName = packageFQName + [interner.intern("Map")]

            func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                case let .classType(classType):
                    return sema.symbols.symbol(classType.classSymbol)?.fqName
                default:
                    return nil
                }
            }

            let candidates = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern("mapValuesTo")]).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      nominalOwnerFQName(for: receiverType) == mapFQName
                else {
                    return false
                }
                return true
            }
            let symbol = try #require(candidates.first, "Expected bundled source for Map.mapValuesTo")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
            #expect(sema.symbols.symbol(symbol)?.fqName == packageFQName + [interner.intern("mapValuesTo")])

            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.parameterTypes.count == 2)
            #expect(signature.returnType == signature.parameterTypes[0])
        }
    }

    @Test
    func testMutableMapPutAllUsesProjectedMapParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let symbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableMap"),
                interner.intern("putAll"),
            ]))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            let parameterType = try #require(signature.parameterTypes.first)

            guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                Issue.record("Expected MutableMap.putAll to take a map type"); return
            }
            #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Map")
            guard classType.args.count == 2,
                  case let .out(keyType) = classType.args[0],
                  case let .out(valueType) = classType.args[1],
                  case .typeParam = sema.types.kind(of: keyType),
                  case .typeParam = sema.types.kind(of: valueType)
            else {
                Issue.record("Expected MutableMap.putAll parameter to use projected Map<K, V>"); return
            }
        }
    }

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildListCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildList"
            })
            let buildListType = try #require(sema.bindings.exprType(for: buildListCall))
            guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                Issue.record("Expected buildList(capacity) to produce a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
            guard case let .out(elementType) = try #require(listType.args.first) else {
                Issue.record("Expected List element type argument"); return
            }
            #expect(elementType == sema.types.intType)
        }
    }

    @Test
    func testListZipWithNextOverloadsInferReturnTypes() throws {
        let source = """
        fun pairs(values: List<Int>) = values.zipWithNext()
        fun gaps(values: List<Int>) = values.zipWithNext { left, right -> right - left }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.zipWithNext overloads to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            func projectedType(_ projection: TypeArg) -> TypeID? {
                switch projection {
                case let .invariant(type), let .out(type), let .in(type):
                    return type
                case .star:
                    return nil
                }
            }

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let noArgCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "zipWithNext" && args.isEmpty
            })
            let transformCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "zipWithNext" && args.count == 1
            })

            let noArgType = try #require(sema.bindings.exprType(for: noArgCall))
            guard case let .classType(noArgListType) = sema.types.kind(of: noArgType),
                  let pairType = projectedType(try #require(noArgListType.args.first)),
                  case let .classType(pairClassType) = sema.types.kind(of: pairType)
            else {
                Issue.record("Expected zipWithNext() to return List<Pair<Int, Int>>"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(noArgListType.classSymbol)?.name)) == "List")
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(pairClassType.classSymbol)?.name)) == "Pair")
            #expect(pairClassType.args.compactMap(projectedType) == [sema.types.intType, sema.types.intType])

            let transformType = try #require(sema.bindings.exprType(for: transformCall))
            guard case let .classType(transformListType) = sema.types.kind(of: transformType),
                  let transformElementType = projectedType(try #require(transformListType.args.first))
            else {
                Issue.record("Expected zipWithNext(transform) to return List<Int>"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(transformListType.classSymbol)?.name)) == "List")
            #expect(transformElementType == sema.types.intType)
        }
    }

    @Test
    func testListZipUsesRuntimeExternalLinkAndReturnsPairList() throws {
        let source = """
        fun zipValues(values: List<Int>, labels: List<String>) = values.zip(labels)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.zip to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "zip" && args.count == 1
            })

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            let fileID = try #require(sema.symbols.sourceFileID(for: chosenCallee))
            #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListWindowChunk.kt")

            let callType = try #require(sema.bindings.exprType(for: callExpr))
            guard case let .classType(listType) = sema.types.kind(of: callType) else {
                Issue.record("Expected List.zip to return a List type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
            let pairType: TypeID
            switch try #require(listType.args.first) {
            case let .invariant(type), let .out(type), let .in(type):
                pairType = type
            case .star:
                Issue.record("Expected List.zip to return a concrete Pair projection"); return
            }
            guard case let .classType(pairClassType) = sema.types.kind(of: pairType) else {
                Issue.record("Expected List.zip to return List<Pair<Int, String>>, got \(sema.types.kind(of: pairType))"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(pairClassType.classSymbol)?.name)) == "Pair")
            #expect(pairClassType.args.count == 2)

            let firstArgument: TypeID
            switch pairClassType.args[0] {
            case let .invariant(type), let .out(type), let .in(type):
                firstArgument = type
            case .star:
                Issue.record("Expected concrete Pair first argument"); return
            }
            let secondArgument: TypeID
            switch pairClassType.args[1] {
            case let .invariant(type), let .out(type), let .in(type):
                secondArgument = type
            case .star:
                Issue.record("Expected concrete Pair second argument"); return
            }
            #expect(firstArgument == sema.types.intType)
            #expect(secondArgument == sema.types.stringType)
        }
    }

    @Test
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

    @Test
    func testListFlatMapIndexedBindsToBundledSource() throws {
        let source = """
        fun render(values: List<String>) {
            val result: List<Int> = values.flatMapIndexed { index, value -> listOf(index + value.length) }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try #require(ctx.sema)
            let sourceFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("flatMapIndexed"),
            ]
            let symbols = sema.symbols.lookupAll(fqName: sourceFQName)
            let listFlatMapIndexedSymbol = try #require(symbols.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      let (receiverClassType, _) = resolveClassTypeSymbol(receiverType, sema: sema),
                      let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol)
                else { return false }
                return ctx.interner.resolve(receiverSymbol.name) == "List"
            }, "Expected bundled source List.flatMapIndexed overload")

            let symbolInfo = try #require(sema.symbols.symbol(listFlatMapIndexedSymbol))
            #expect(!symbolInfo.flags.contains(.synthetic), "flatMapIndexed must be a bundled source declaration")
            #expect(sema.symbols.externalLinkName(for: listFlatMapIndexedSymbol) == nil, "source flatMapIndexed must not link to runtime")

            let symbol = listFlatMapIndexedSymbol
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                  let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
            else {
                Issue.record("Expected List.flatMapIndexed to return List<R>"); return
            }
            #expect(ctx.interner.resolve(returnSymbol.name) == "List")

            let transformType = try #require(signature.parameterTypes.first)
            guard case let .functionType(functionType) = sema.types.kind(of: transformType),
                  let (_, transformReturnSymbol) = resolveClassTypeSymbol(functionType.returnType, sema: sema)
            else {
                Issue.record("Expected List.flatMapIndexed transform to return List<R>"); return
            }
            #expect(functionType.params.count == 2, "Expected flatMapIndexed transform to take (index, element)")
            #expect(functionType.params.first == sema.types.intType)
            #expect(functionType.params.last != sema.types.intType, "Second transform parameter should be the list element type, not Int")
            #expect(ctx.interner.resolve(transformReturnSymbol.name) == "List")
        }
    }

    @Test
    func testListToBooleanArrayResolvesToSourceBackedDeclaration() throws {
        let source = """
        fun convert(values: List<Boolean>) {
            values.toBooleanArray()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toBooleanArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            // KSP-628: source-backed (ArrayConversions.kt), no direct runtime link.
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            let resultType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toBooleanArray to return BooleanArray"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "BooleanArray")
        }
    }

    @Test
    func testListToShortArrayResolvesToSourceBackedDeclaration() throws {
        let source = """
        fun convert(values: List<Short>) {
            values.toShortArray()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toShortArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            // KSP-628: source-backed (ArrayConversions.kt), no direct runtime link.
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            let resultType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toShortArray to return ShortArray"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "ShortArray")
        }
    }

    @Test
    func testListToDoubleArrayResolvesToSourceBackedDeclaration() throws {
        let source = """
        fun convert(values: List<Double>) {
            values.toDoubleArray()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toDoubleArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            // KSP-628: source-backed (ArrayConversions.kt), no direct runtime link.
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            let resultType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toDoubleArray to return DoubleArray"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "DoubleArray")
        }
    }

    @Test
    func testListToFloatArrayResolvesToSourceBackedDeclaration() throws {
        let source = """
        fun convert(values: List<Float>) {
            values.toFloatArray()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toFloatArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            // KSP-628: source-backed (ArrayConversions.kt), no direct runtime link.
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            let resultType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toFloatArray to return FloatArray"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "FloatArray")
        }
    }
}
#endif
