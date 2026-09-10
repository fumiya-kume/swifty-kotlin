#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// RF-LOWER-CALL-001: pin the *production* routing of the `buildList` /
/// `buildSet` / `buildMap` DSL before RF-LOWER-CALL-004〜006 delete the legacy
/// `__kk_build_*` rewrite in `CollectionLiteralLoweringPass+CallRewriteFactories.swift`.
///
/// `CollectionLiteralLoweringTests` covers the same three names, but every one
/// of those cases hand-builds `.call(symbol: nil, ...)` KIR against a
/// `KIRContext` without a `SemaModule`, which short-circuits
/// `isStdlibBuilderDSLCall` at its `guard let symbol else { return true }`.
/// They therefore prove only that the rewrite still exists — never that any
/// real Kotlin input reaches it.  The tests below drive the same pass from
/// source, so the deletion premises rest on the production path rather than on
/// the legacy conversion tests.
@Suite
struct BuilderDSLLoweringRoutingTests {
    /// The legacy runtime entry points the rewrite substitutes.  Matched
    /// exactly: the source-backed helper `__kk_builder_list_new` also starts
    /// with `__kk_build`.
    private static let legacyBuilderRuntimeCallees: Set<String> = [
        "__kk_build_list", "__kk_build_list_with_capacity",
        "__kk_build_set", "__kk_build_set_with_capacity",
        "__kk_build_map", "__kk_build_map_with_capacity",
    ]

    private static let builderDSLSource = """
    fun main() {
        val listNoCapacity = buildList { add(1) }
        val listWithCapacity = buildList(4) { add(2) }
        val setNoCapacity = buildSet { add("x") }
        val setWithCapacity = buildSet(4) { add("y") }
        val mapNoCapacity = buildMap { put("k", 1) }
        val mapWithCapacity = buildMap(4) { put("k", 2) }
    }
    """

    /// Every `.call` in `body` whose callee is one of the three builder names,
    /// paired with its argument count (1 = no capacity, 2 = capacity overload).
    private static func builderCalls(
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> [(name: String, argumentCount: Int, symbol: SymbolID?)] {
        body.compactMap { instruction in
            guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction else { return nil }
            let name = interner.resolve(callee)
            guard ["buildList", "buildSet", "buildMap"].contains(name) else { return nil }
            return (name, arguments.count, symbol)
        }
    }

    private static func runCollectionLiteralPassOnly(_ ctx: CompilationContext) throws -> KIRModule {
        let module = try #require(ctx.kir)
        let kirCtx = KIRContext(
            diagnostics: ctx.diagnostics,
            options: ctx.options,
            interner: ctx.interner,
            sema: ctx.sema
        )
        module.scanFeatures()
        try CollectionLiteralLoweringPass().run(module: module, ctx: kirCtx)
        return module
    }

    // MARK: - source-backed routing (the production path)

    /// All six overloads survive `CollectionLiteralLoweringPass` untouched, so
    /// the bundled `CollectionBuilders.kt` body is what the backend inlines.
    @Test
    func sourceBackedBuilderCallsSurviveCollectionLiteralLowering() throws {
        try withTemporaryFile(contents: Self.builderDSLSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BuilderDSLRouting",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            let builderCalls = Self.builderCalls(in: body, interner: ctx.interner)

            let survivors = Set(builderCalls.map { "\($0.name)/\($0.argumentCount)" })
            #expect(
                survivors == [
                    "buildList/1", "buildList/2",
                    "buildSet/1", "buildSet/2",
                    "buildMap/1", "buildMap/2",
                ],
                "every capacity/no-capacity overload must stay a source call; got: \(survivors)"
            )
            #expect(
                callees.allSatisfy { !Self.legacyBuilderRuntimeCallees.contains($0) },
                "no __kk_build_* rewrite may reach production KIR; callees: \(callees)"
            )
        }
    }

    /// The reason the rewrite is skipped: the resolved callee misses every
    /// `true`-returning branch of `isStdlibBuilderDSLCall` — the symbol is
    /// present (not `nil`), not `.synthetic`, carries no `externalLinkName`,
    /// and is source-backed by `CollectionBuilders.kt`.
    @Test
    func sourceBackedBuilderCalleesMissEveryRewriteBranch() throws {
        try withTemporaryFile(contents: Self.builderDSLSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BuilderDSLRoutingSymbols",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let builderCalls = Self.builderCalls(in: body, interner: ctx.interner)
            #expect(builderCalls.count == 6, "expected six builder calls; got \(builderCalls.count)")

            let sema = try #require(ctx.sema)
            for call in builderCalls {
                let label = "\(call.name)/\(call.argumentCount)"
                let symbolID = try #require(call.symbol, "\(label): production KIR must carry a resolved symbol")
                let symbol = try #require(sema.symbols.symbol(symbolID), "\(label): symbol must be in the table")

                #expect(!symbol.flags.contains(.synthetic), "\(label) must not resolve to a synthetic stub")
                #expect(
                    sema.symbols.externalLinkName(for: symbolID) == nil,
                    "\(label) must not carry an external link name"
                )
                #expect(sema.symbols.isSourceBackedSymbol(symbolID), "\(label) must be source-backed")

                let fileID = try #require(sema.symbols.sourceFileID(for: symbolID), "\(label): missing source file")
                #expect(
                    ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/CollectionBuilders.kt",
                    "\(label) must resolve to CollectionBuilders.kt; got \(String(describing: ctx.sourceManager.path(of: fileID)))"
                )
            }

            // KSP-697's residual buildList stub must not even be registered
            // when the bundled stdlib is present, so overload resolution can
            // never pick it over the Kotlin declarations above.
            let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)
            for name in ["buildList", "buildSet", "buildMap"] {
                let syntheticOverloads = sema.symbols
                    .lookupAll(fqName: packageFQName + [ctx.interner.intern(name)])
                    .filter { sema.symbols.symbol($0)?.flags.contains(.synthetic) == true }
                #expect(
                    syntheticOverloads.isEmpty,
                    "\(name) must have no synthetic overload alongside the bundled stdlib"
                )
            }
        }
    }

    /// User functions that merely share the DSL names — including the receiver
    /// lambda shape that would collide with the rewrite's `arguments.count == 2`
    /// capacity mapping — must be left alone.  `Scripts/diff_cases/builder_dsl_shadowing.kt`
    /// only covers the `Int -> Int` shape, which never reaches the mapping.
    @Test
    func userDefinedBuilderNamedFunctionsAreNotRewritten() throws {
        let source = """
        fun buildList(capacity: Int, block: MutableList<Int>.() -> Unit): Int {
            val holder = mutableListOf<Int>()
            holder.block()
            return capacity + holder.size
        }

        fun buildSet(block: MutableList<Int>.() -> Unit): Int {
            val holder = mutableListOf<Int>()
            holder.block()
            return holder.size
        }

        fun main() {
            val a = buildList(3) { add(1); add(2) }
            val b = buildSet { add(9) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BuilderDSLShadowing",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("buildList"), "the user buildList must stay; callees: \(callees)")
            #expect(callees.contains("buildSet"), "the user buildSet must stay; callees: \(callees)")
            #expect(
                callees.allSatisfy { !Self.legacyBuilderRuntimeCallees.contains($0) },
                "a user function may never be rewritten to a runtime builder; callees: \(callees)"
            )
        }
    }

    // MARK: - builder entry points require the bundled stdlib

    /// Both buildList overloads are supplied by CollectionBuilders.kt. Without
    /// that source, neither registry may recreate a synthetic entry point.
    @Test(arguments: ["buildList<Int> { add(1) }", "buildList<Int>(4) { add(2) }"])
    func noStdlibHasNoBuildListEntryPoint(expression: String) throws {
        let source = "fun main() { val result = \(expression) }"
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BuilderDSLNoStdlib",
                emit: .kirDump,
                includeStdlib: false
            )
            try runToKIR(ctx)

            let unresolved = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0023" }
            #expect(
                unresolved.contains { $0.message.contains("'buildList'") },
                "buildList must require stdlib source; diagnostics: \(ctx.diagnostics.diagnostics)"
            )
            let sema = try #require(ctx.sema)
            #expect(sema.symbols.lookup(fqName: ["kotlin", "collections", "buildList"].map(ctx.interner.intern)) == nil)
        }
    }

    /// `buildSet` / `buildMap` have no residual synthetic stub, so without the
    /// bundled stdlib they do not resolve at all.  No production input can
    /// therefore reach the `__kk_build_set*` / `__kk_build_map*` rewrites:
    /// RF-LOWER-CALL-005/006 have no fallback consumer to preserve.
    @Test
    func noStdlibHasNoBuildSetOrBuildMapEntryPoint() throws {
        let source = """
        fun main() {
            val a = buildSet<Int> { add(1) }
            val b = buildMap<String, Int> { put("k", 1) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BuilderDSLNoStdlibSetMap",
                emit: .kirDump,
                includeStdlib: false
            )
            try runToKIR(ctx)

            let unresolved = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0023" }
            #expect(
                unresolved.contains { $0.message.contains("'buildSet'") },
                "buildSet must be unresolved without stdlib; diagnostics: \(ctx.diagnostics.diagnostics)"
            )
            #expect(
                unresolved.contains { $0.message.contains("'buildMap'") },
                "buildMap must be unresolved without stdlib; diagnostics: \(ctx.diagnostics.diagnostics)"
            )
        }
    }
}
#endif
