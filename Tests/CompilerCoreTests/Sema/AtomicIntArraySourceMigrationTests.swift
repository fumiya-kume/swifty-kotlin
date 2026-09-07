#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1089: the legacy AtomicIntArray constructor overloads are source-backed
/// while the allocation and residual member operations retain their runtime ABI.
@Suite(.serialized)
struct AtomicIntArraySourceMigrationTests {
    @Test
    func testConstructorsAreSourceBackedAndUseTheExpectedVisibility() throws {
        let ctx = makeContextFromSource("""
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        import kotlin.concurrent.AtomicIntArray

        fun fromSize(size: Int): AtomicIntArray = AtomicIntArray(size)
        fun fromArray(values: IntArray): AtomicIntArray = AtomicIntArray(values)
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected AtomicIntArray constructor source to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let constructorFQName = ["kotlin", "concurrent", "AtomicIntArray"].map(interner.intern)
        let arraySymbol = try #require(sema.symbols.lookup(fqName: constructorFQName))
        let arrayType = sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let intArraySymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "IntArray"].map(interner.intern))
        )
        let intArrayType = sema.types.make(.classType(ClassType(
            classSymbol: intArraySymbol,
            args: [],
            nullability: .nonNull
        )))

        let sizeConstructor = try #require(sema.symbols.lookupAll(fqName: constructorFQName).first { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.parameterTypes == [sema.types.intType]
                && signature.returnType == arrayType
        })
        let sizeInfo = try #require(sema.symbols.symbol(sizeConstructor))
        #expect(sizeInfo.visibility == .public)
        #expect(!sizeInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(sizeConstructor))
        #expect(sema.symbols.externalLinkName(for: sizeConstructor) == "kk_atomic_int_array_create")

        let storageConstructor = try #require(sema.symbols.lookupAll(fqName: constructorFQName).first { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.parameterTypes == [intArrayType]
                && signature.returnType == arrayType
        })
        let storageInfo = try #require(sema.symbols.symbol(storageConstructor))
        #expect(storageInfo.visibility == .internal)
        #expect(!storageInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(storageConstructor))
        #expect(sema.symbols.externalLinkName(for: storageConstructor) == nil)

        let sourceFileID = try #require(sema.symbols.sourceFileID(for: sizeConstructor))
        #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/concurrent/AtomicIntArray/Stdlib.kt")
        #expect(sema.symbols.sourceFileID(for: storageConstructor) == sourceFileID)

        let ast = try #require(ctx.ast)
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, _, range) = ast.arena.expr(exprID),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  interner.resolve(name) == "AtomicIntArray"
            else {
                return nil
            }
            return exprID
        }
        #expect(calls.count == 2)

        let chosenCallees = try calls.map { call in
            try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        }
        #expect(chosenCallees.contains(sizeConstructor))
        #expect(chosenCallees.contains(storageConstructor))
        #expect(chosenCallees.allSatisfy { sema.symbols.isSourceBackedSymbol($0) })
        #expect(calls.allSatisfy { sema.bindings.stdlibSpecialCallKind(for: $0) == nil })
    }
}
#endif
