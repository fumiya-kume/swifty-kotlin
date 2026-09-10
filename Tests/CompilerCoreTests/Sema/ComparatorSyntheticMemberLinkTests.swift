#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ComparatorSyntheticMemberLinkTests {
    private func allExprIDs(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }

    private func sourceBackedComparatorExtension(
        named name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = ["kotlin", "comparisons", name].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            guard sema.symbols.externalLinkName(for: symbolID) == nil,
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  let receiver = signature.receiverType,
                  case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiver)),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            return symbol.fqName.map { interner.resolve($0) } == ["kotlin", "Comparator"]
        }
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func allExprIDs(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var result: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { result.append(exprID) }
        }
        return result
    }

    // MARK: - Consolidated source-backed comparator member link tests

    @Test
    func testComparatorSyntheticMemberLinks() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
            """
            fun render1(values: List<Int>) {
                val comparator = compareBy<Int> { it % 10 }.thenComparator { a, b -> b.compareTo(a) }
                values.sortedWith(comparator)
            }
            """,
            """
            fun render2(values: List<Int>) {
                val comparator = compareByDescending<Int> { it % 10 }.thenBy { it / 10 }
                values.sortedWith(comparator)
            }
            """,
            """
            fun render3(values: List<Int>) {
                val comparator = compareBy<Int> { it % 10 }.thenDescending { a, b -> b.compareTo(a) }
                values.sortedWith(comparator)
            }
            """,
            """
            fun render4(values: List<Int>) {
                val comparator = compareBy<Int> { it % 10 }.thenBy { it / 10 }
                values.sortedWith(comparator)
            }
            """,
            """
            fun render5(values: List<Int>) {
                val comparator = compareBy<Int> { it % 10 }
                comparator.compare(13, 24)
                values.sortedWith(comparator)
            }
            """,
            """
            import kotlin.comparisons.thenDescending

            fun render6(values: List<Int>) {
                val comparator = compareBy<Int> { it % 10 }.thenDescending { a, b -> b.compareTo(a) }
                values.sortedWith(comparator)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected comparator synthetic member tests to type-check without diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            // paths[0] is the noop source; paths[1...] map to the original sample sources.

            // === testComparatorThenComparatorUsesBundledStdlibFunction ===

            do {

                let samplePath = paths[1]

                let callExpr = try #require(firstExprID(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "thenComparator"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenComparator to resolve to bundled stdlib source")

            }

            // === testCompareByDescendingUsesBundledStdlibFunction ===

            do {

                let samplePath = paths[2]

                let callExpr = try #require(allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(callee) else {
                        return false
                    }
                    return interner.resolve(calleeName) == "compareByDescending"
                }.first)

                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected compareByDescending to resolve to bundled stdlib source")

            }

            // === testComparatorThenDescendingUsesBundledStdlibFunction ===

            do {

                let samplePath = paths[3]

                let callExpr = try #require(firstExprID(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "thenDescending"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenDescending to resolve to bundled stdlib source")
                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let parameterType = try #require(signature.parameterTypes.first)
                guard case .functionType = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected thenDescending lambda syntax to resolve to the function-parameter overload")
                    return
                }

            }

            // === testImportedComparatorThenDescendingLambdaUsesLambdaOverload ===

            do {

                let samplePath = paths[6]

                let callExpr = try #require(firstExprID(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "thenDescending"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected imported thenDescending to resolve to bundled stdlib source")
                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let parameterType = try #require(signature.parameterTypes.first)
                guard case .functionType = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected imported thenDescending lambda syntax to resolve to the function-parameter overload")
                    return
                }

            }

            // === testComparatorThenByUsesBundledStdlibFunction ===

            do {

                let samplePath = paths[4]

                let callExpr = try #require(firstExprID(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "thenBy"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenBy to resolve to bundled stdlib source")

            }

            // === testComparatorCompareMemberResolves ===

            do {

                let samplePath = paths[5]

                let callExpr = try #require(allExprIDs(in: ast, path: samplePath, ctx: ctx) { id, expr in
                    // Skip bundled stdlib files (FileID 0 = collections, 1 = text, 2 = sequences, 3 = time, 4 = file IO);
                    // maxWith/minWith bodies also call comparator.compare, which would
                    // otherwise shadow the user's call with a lower ExprID.
                    if let range = ast.arena.exprRange(id), range.start.file.rawValue < 5 {
                        return false
                    }
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "compare"
                }.last)

                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosenCallee))
                #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "Comparator", "compare"], "Expected Comparator.compare to resolve to the source-backed Comparator member")

            }

            // === testComparatorThenComparatorIsRegisteredFromBundledStdlib ===

            do {

                let samplePath = paths[0]

                let symbolID = try #require(sourceBackedComparatorExtension(
                    named: "thenComparator",
                    sema: sema,
                    interner: interner
                ), "Expected Comparator.thenComparator to be registered from bundled stdlib source")
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.thenComparator to be source-backed")

            }

            // === testComparatorThenDescendingIsRegisteredFromBundledStdlib ===

            do {

                let samplePath = paths[0]

                let symbolID = try #require(sourceBackedComparatorExtension(
                    named: "thenDescending",
                    sema: sema,
                    interner: interner
                ), "Expected Comparator.thenDescending to be registered from bundled stdlib source")
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.thenDescending to be source-backed")

            }

        }
    }

    @Test
    func testExplicitComparatorImplementationUsesSourceBackedInterface() throws {
        let source = """
        class ReverseComparator : Comparator<Int> {
            override fun compare(a: Int, b: Int): Int = b - a
        }

        fun useExplicitComparator(): Int {
            val comparator: Comparator<Int> = ReverseComparator()
            return comparator.compare(3, 5)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(
                inputs: [path],
                allowDefaultStdlibLibrary: false
            )
            try runSema(context)
            #expect(!context.diagnostics.hasError)

            let sema = try #require(context.sema)
            let comparator = try #require(
                sema.symbols.lookup(fqName: [
                    context.interner.intern("kotlin"),
                    context.interner.intern("Comparator")
                ])
            )
            let comparatorInfo = try #require(sema.symbols.symbol(comparator))
            #expect(!comparatorInfo.flags.contains(.synthetic))
            let comparatorFileID = try #require(sema.symbols.sourceFileID(for: comparator))
            #expect(context.sourceManager.path(of: comparatorFileID) == "__bundled_kotlin/Comparator.kt")

            let compare = try #require(
                sema.symbols.lookup(fqName: [
                    context.interner.intern("kotlin"),
                    context.interner.intern("Comparator"),
                    context.interner.intern("compare")
                ])
            )
            let compareInfo = try #require(sema.symbols.symbol(compare))
            #expect(!compareInfo.flags.contains(.synthetic))
        }
    }
}
#endif
