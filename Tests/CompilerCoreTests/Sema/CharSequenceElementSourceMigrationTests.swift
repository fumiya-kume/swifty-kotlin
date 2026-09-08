@testable import CompilerCore
import Testing

@Suite
struct CharSequenceElementSourceMigrationTests {
    @Test
    func elementFamilyBindsToInlineBundledDeclarations() throws {
        let context = makeContextFromSource("""
        fun read(source: CharSequence, index: Int): Char = source.elementAt(index)
        fun readOrElse(source: CharSequence, index: Int): Char =
            source.elementAtOrElse(index) { if (it < 0) '-' else '+' }
        fun readOrNull(source: CharSequence, index: Int): Char? = source.elementAtOrNull(index)
        fun nonLocal(source: CharSequence): Char {
            return source.elementAtOrElse(-1) { return 'x' }
        }
        """)
        try runSema(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map(\.message))")
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let names: Set<String> = ["elementAt", "elementAtOrElse", "elementAtOrNull"]
        var calls = 0
        for index in ast.arena.exprs.indices {
            let expression = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, name, _, _, range) = ast.arena.expr(expression),
                  context.sourceManager.origin(of: range.start.file) == .user,
                  names.contains(context.interner.resolve(name))
            else { continue }
            calls += 1
            let binding = try #require(sema.bindings.callBinding(for: expression))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let file = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(context.sourceManager.path(of: file) == "__bundled_kotlin/text/StringHOF.kt")
            #expect(!symbol.flags.contains(.synthetic))
            #expect(symbol.flags.contains(.inlineFunction))
            #expect(sema.symbols.externalLinkName(for: symbol.id) == nil)
            let signature = try #require(sema.symbols.functionSignature(for: symbol.id))
            let expectedReturn = context.interner.resolve(name) == "elementAtOrNull"
                ? sema.types.makeNullable(sema.types.charType) : sema.types.charType
            #expect(signature.returnType == expectedReturn)
        }
        #expect(calls == 4)
    }
}
