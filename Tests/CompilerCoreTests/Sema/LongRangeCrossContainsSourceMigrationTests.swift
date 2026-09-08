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

    @Test
    func literalAndTypedOperandsKeepKotlinOverloadPriority() throws {
        let source = """
        operator fun LongRange.contains(value: Int): Boolean = false

        fun literalDirect(range: LongRange): Boolean = range.contains(5)
        fun literalIn(range: LongRange): Boolean = 5 in range
        fun largeLiteralDirect(range: LongRange): Boolean = range.contains(2147483648)
        fun largeLiteralIn(range: LongRange): Boolean = 2147483648 in range
        fun intDirect(range: LongRange, value: Int): Boolean = range.contains(value)
        fun intIn(range: LongRange, value: Int): Boolean = value in range
        fun byteDirect(range: LongRange, value: Byte): Boolean = range.contains(value)
        fun byteIn(range: LongRange, value: Byte): Boolean = value in range
        fun shortDirect(range: LongRange, value: Short): Boolean = range.contains(value)
        fun shortIn(range: LongRange, value: Short): Boolean = value in range
        fun longDirect(range: LongRange, value: Long): Boolean = range.contains(value)
        fun longIn(range: LongRange, value: Long): Boolean = value in range
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected LongRange overload controls to type-check: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first { ctx.sourceManager.origin(of: $0) == .user })
        let longRangeType = try #require(sema.symbols.lookup(fqName: ["kotlin", "ranges", "LongRange"].map(ctx.interner.intern)))
        let longRangeReceiver = sema.types.make(.classType(ClassType(
            classSymbol: longRangeType,
            args: [],
            nullability: .nonNull
        )))

        var parameterTypes: [TypeID] = []
        var userIntBindings = 0
        for offset in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(offset))
            guard let exprRange = ast.arena.exprRange(exprID),
                  exprRange.start.file == userFileID,
                  let binding = sema.bindings.callBinding(for: exprID),
                  let signature = sema.symbols.functionSignature(for: binding.chosenCallee),
                  signature.receiverType == longRangeReceiver,
                  signature.parameterTypes.count == 1
            else {
                continue
            }
            parameterTypes.append(signature.parameterTypes[0])
            if signature.parameterTypes[0] == sema.types.intType,
               let sourceFileID = sema.symbols.sourceFileID(for: binding.chosenCallee),
               ctx.sourceManager.origin(of: sourceFileID) == .user
            {
                userIntBindings += 1
            }
        }

        // The LongRange base-element `in` calls use the existing runtime dispatch
        // and therefore do not carry a source-level CallBinding.
        #expect(parameterTypes.count == 11, "Expected source bindings for cross-type/direct calls, got \(parameterTypes.count)")
        #expect(parameterTypes.filter { $0 == sema.types.longType }.count == 5)
        #expect(parameterTypes.filter { $0 == sema.types.intType }.count == 2)
        #expect(parameterTypes.filter { $0 == sema.types.byteType }.count == 2)
        #expect(parameterTypes.filter { $0 == sema.types.shortType }.count == 2)
        #expect(userIntBindings == 2, "Explicit Int operands must select the user LongRange.contains(Int) extension")
    }
}
#endif
