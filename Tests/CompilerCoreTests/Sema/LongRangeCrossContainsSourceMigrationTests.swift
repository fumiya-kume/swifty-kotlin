#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1287: LongRange's signed primitive contains overloads must stay
/// source-backed so explicit calls and `in` use the same Kotlin declarations.
@Suite
struct LongRangeCrossContainsSourceMigrationTests {
    private struct ExpectedOverload {
        let type: TypeID
        let name: String
    }

    @Test
    func crossTypeContainsDeclarationsAreSourceBacked() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let longRangeFQName = ["kotlin", "ranges", "LongRange"].map(interner.intern)
        let longRangeSymbol = try #require(sema.symbols.lookup(fqName: longRangeFQName))
        let expected = [
            ExpectedOverload(type: sema.types.byteType, name: "Byte"),
            ExpectedOverload(type: sema.types.intType, name: "Int"),
            ExpectedOverload(type: sema.types.shortType, name: "Short"),
        ]

        let containsName = ["kotlin", "ranges", "contains"].map(interner.intern)
        for overload in expected {
            let symbols = sema.symbols.lookupAll(fqName: containsName).filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      signature.receiverType == sema.types.make(.classType(ClassType(
                          classSymbol: longRangeSymbol,
                          args: [],
                          nullability: .nonNull
                      ))),
                      signature.parameterTypes == [overload.type],
                      sema.symbols.isSourceBackedSymbol(symbolID),
                      sema.symbols.externalLinkName(for: symbolID) == nil,
                      let sourceFileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/ranges/RangeHOF.kt"
            }

            #expect(
                symbols.count == 1,
                "Expected one source-backed LongRange.contains(\(overload.name)), got: \(symbols)"
            )
        }
    }

    @Test
    func directCallsBindToCrossTypeSourceDefinitions() throws {
        let source = """
        fun byteContains(range: LongRange, value: Byte): Boolean = range.contains(value)
        fun intContains(range: LongRange, value: Int): Boolean = range.contains(value)
        fun shortContains(range: LongRange, value: Short): Boolean = range.contains(value)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected LongRange contains calls to type-check: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first { ctx.sourceManager.origin(of: $0) == .user })
        let expectedTypes: Set<TypeID> = [sema.types.byteType, sema.types.intType, sema.types.shortType]
        var actualTypes = Set<TypeID>()

        for offset in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(offset))
            guard let range = ast.arena.exprRange(exprID),
                  range.start.file == userFileID,
                  case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                  ctx.interner.resolve(callee) == "contains",
                  let binding = sema.bindings.callBinding(for: exprID),
                  let signature = sema.symbols.functionSignature(for: binding.chosenCallee),
                  let parameterType = signature.parameterTypes.first
            else {
                continue
            }
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
            actualTypes.insert(parameterType)
        }

        #expect(actualTypes == expectedTypes, "Missing LongRange cross-type bindings: \(expectedTypes.subtracting(actualTypes))")
    }
}
#endif
