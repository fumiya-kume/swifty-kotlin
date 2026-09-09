#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1404: CharSequence.sumOf is provided by the bundled Kotlin source and
/// selects the overload whose selector returns the requested numeric type.
@Suite
struct CharSequenceSumSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func sumOfDeclarationsAreSourceBacked() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("CharSequence")])
        )
        let sumOfFQName = [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("sumOf"),
        ]
        let declarations = sema.symbols.lookupAll(fqName: sumOfFQName).filter { id in
            guard let symbol = sema.symbols.symbol(id),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: id),
                  let signature = sema.symbols.functionSignature(for: id),
                  let receiver = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiver)
            else {
                return false
            }
            return receiverClass.classSymbol == charSequenceSymbol
                && ctx.sourceManager.path(of: fileID) == sourcePath
        }

        #expect(declarations.count == 5, "Expected five CharSequence.sumOf source declarations")
        #expect(Set(declarations.compactMap { sema.symbols.functionSignature(for: $0)?.returnType }) == Set([
            sema.types.doubleType,
            sema.types.intType,
            sema.types.longType,
            sema.types.uintType,
            sema.types.ulongType,
        ]))
        #expect(declarations.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        #expect(declarations.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.inlineFunction) == true })
        let annotatedReturns = Set(declarations.filter { id in
            sema.symbols.annotations(for: id).contains {
                KnownCompilerAnnotation.overloadResolutionByLambdaReturnType.matches($0.annotationFQName)
            }
        }.compactMap { sema.symbols.functionSignature(for: $0)?.returnType })
        #expect(annotatedReturns == Set([
            sema.types.doubleType,
            sema.types.longType,
            sema.types.ulongType,
        ]))
    }

    @Test
    func sumOfCallsSelectExactNumericOverloads() throws {
        let source = """
        fun sumDouble(value: CharSequence): Double = value.sumOf { it.code.toDouble() }
        fun sumInt(value: CharSequence): Int = value.sumOf { it.code }
        fun sumLong(value: CharSequence): Long = value.sumOf { it.code.toLong() }
        fun sumUInt(value: CharSequence): UInt = value.sumOf { it.code.toUInt() }
        fun sumULong(value: CharSequence): ULong = value.sumOf { it.code.toULong() }
        fun sumString(value: String): Int = value.sumOf { it.code }
        fun sumBuilder(value: StringBuilder): Long = value.sumOf { it.code.toLong() }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(id),
                  ctx.interner.resolve(callee) == "sumOf",
                  let range = ast.arena.exprRange(id),
                  range.start.file == userFileID
            else {
                return nil
            }
            return id
        }
        let expectedReturns = [
            sema.types.doubleType,
            sema.types.intType,
            sema.types.longType,
            sema.types.uintType,
            sema.types.ulongType,
            sema.types.intType,
            sema.types.longType,
        ]
        #expect(calls.count == expectedReturns.count, "Expected seven CharSequence.sumOf calls")
        for (call, expectedReturn) in zip(calls, expectedReturns) {
            let binding = try #require(sema.bindings.callBinding(for: call))
            let chosen = binding.chosenCallee
            let fileID = try #require(sema.symbols.sourceFileID(for: chosen))
            #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            #expect(signature.returnType == expectedReturn)
            let selector = try #require(signature.parameterTypes.first)
            guard case let .functionType(selectorType) = sema.types.kind(of: selector) else {
                Issue.record("Expected CharSequence.sumOf selector to be a function type")
                continue
            }
            #expect(selectorType.params == [sema.types.charType])
            #expect(selectorType.returnType == expectedReturn)
        }
    }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics
        .map { diagnostic in
            guard let range = diagnostic.primaryRange else {
                return "\(diagnostic.code): \(diagnostic.message)"
            }
            let position = ctx.sourceManager.lineColumn(of: range.start)
            return "\(ctx.sourceManager.path(of: range.start.file)):\(position.line):\(position.column): \(diagnostic.code): \(diagnostic.message)"
        }
        .joined(separator: "\n")
}
#endif
