@testable import CompilerCore
import Testing

@Suite
struct CharSequenceGetSourceMigrationTests {
    @Test
    func indexedAccessorsBindToBundledDeclarations() throws {
        let context = makeContextFromSource("""
        fun read(source: CharSequence, index: Int): Char? = source.getOrNull(index)
        fun readOrElse(source: CharSequence, index: Int): Char =
            source.getOrElse(index) { if (it < 0) '-' else '+' }
        fun named(source: CharSequence, value: Char): Char {
            source.getOrElse(defaultValue = { return value }, index = -1)
            return '?'
        }
        """)
        try runSema(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map(\.message))")
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        var calls = 0
        for index in ast.arena.exprs.indices {
            let expression = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, name, _, _, range) = ast.arena.expr(expression),
                  context.sourceManager.origin(of: range.start.file) == .user,
                  ["getOrElse", "getOrNull"].contains(context.interner.resolve(name))
            else { continue }
            calls += 1
            let binding = try #require(sema.bindings.callBinding(for: expression))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let file = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(context.sourceManager.path(of: file) == "__bundled_kotlin/text/StringQuery.kt")
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.externalLinkName(for: symbol.id) == nil)
            let isDefault = context.interner.resolve(name) == "getOrElse"
            #expect(symbol.flags.contains(.inlineFunction) == isDefault)
            let signature = try #require(sema.symbols.functionSignature(for: symbol.id))
            #expect(signature.returnType == (isDefault
                ? sema.types.charType : sema.types.makeNullable(sema.types.charType)))
        }
        #expect(calls == 3)
    }
}
