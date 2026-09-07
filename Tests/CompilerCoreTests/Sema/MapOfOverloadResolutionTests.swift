#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-956: non-empty mapOf calls must use the fixed-Pair or vararg overload
/// selected by arity, while both overloads keep the shared collection lowering.
@Suite
struct MapOfOverloadResolutionTests {
    @Test
    func testSinglePairUsesFixedArityOverload() throws {
        let ctx = makeContextFromSource("""
        fun probe() {
            val pair: Pair<String, Int> = Pair<String, Int>("key", 1)
            val singleton = mapOf(pair)
            val multiple = mapOf(pair, pair)
            println(singleton.size + multiple.size)
        }
        """)

        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let mapCalls = ast.arena.exprs.indices.compactMap { rawID -> ExprID? in
            let exprID = ExprID(rawValue: Int32(rawID))
            guard let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .call(callee, _, args, _) = ast.arena.expr(exprID),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ctx.interner.resolve(name) == "mapOf"
            else {
                return nil
            }
            return (args.count == 1 || args.count == 2) ? exprID : nil
        }
        #expect(mapCalls.count == 2)

        let singlePairCall = try #require(mapCalls.first { exprID in
            guard case let .call(_, _, args, _) = ast.arena.expr(exprID) else { return false }
            return args.count == 1
        })
        let multiplePairCall = try #require(mapCalls.first { exprID in
            guard case let .call(_, _, args, _) = ast.arena.expr(exprID) else { return false }
            return args.count == 2
        })

        let singleBinding = try #require(sema.bindings.callBinding(for: singlePairCall))
        let singleSignature = try #require(sema.symbols.functionSignature(for: singleBinding.chosenCallee))
        #expect(singleSignature.valueParameterIsVararg == [false])
        #expect(singleBinding.parameterMapping == [0: 0])

        let multipleBinding = try #require(sema.bindings.callBinding(for: multiplePairCall))
        let multipleSignature = try #require(sema.symbols.functionSignature(for: multipleBinding.chosenCallee))
        #expect(multipleSignature.valueParameterIsVararg == [true])
        #expect(multipleBinding.parameterMapping == [0: 0, 1: 0])
        #expect(singleBinding.chosenCallee != multipleBinding.chosenCallee)
    }

    /// Regression: an explicit type argument on the vararg `mapOf<K, V>(...)`
    /// overload must be treated as authoritative rather than folded into the
    /// same lub/glb bound pool as the vararg elements' own types. Each `Pair`
    /// argument here upcasts to `Pair<Any?, Number?>` on its own (`Pair` is
    /// declared `out A, out B`), but combining the explicit `Number?` bound
    /// with the elements' actual types (`Int`, `Nothing?`) through `lub()`
    /// used to widen the candidate to `Any?` and report a spurious
    /// "Conflicting bounds for type variable" error (KSWIFTK-TYPE-0001).
    @Test
    func testExplicitTypeArgsAllowVarargPairUpcast() throws {
        let ctx = makeContextFromSource("""
        fun probe() {
            val projected: Map<Any?, Number?> = mapOf<Any?, Number?>("a" to 1, null to null)
            println(projected)
        }
        """)

        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
    }
}
#endif
