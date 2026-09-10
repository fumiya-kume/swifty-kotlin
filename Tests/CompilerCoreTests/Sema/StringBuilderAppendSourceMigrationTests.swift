@testable import CompilerCore
import Testing

@Suite
struct StringBuilderAppendSourceMigrationTests {
    @Test
    func appendLineSelectsTheDeclaredValueTypeInsteadOfAny() throws {
        let context = makeContextFromSource("""
        fun lines(builder: StringBuilder, bool: Boolean, byte: Byte, char: Char, chars: CharArray,
                  sequence: CharSequence?, double: Double, float: Float, int: Int, long: Long,
                  short: Short, string: String?) {
            builder.appendLine(bool)
            builder.appendLine(byte)
            builder.appendLine(char)
            builder.appendLine(chars)
            builder.appendLine(sequence)
            builder.appendLine(double)
            builder.appendLine(float)
            builder.appendLine(int)
            builder.appendLine(long)
            builder.appendLine(short)
            builder.appendLine(string)
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
            guard case let .memberCall(receiver, name, _, arguments, range) = ast.arena.expr(expression),
                  context.sourceManager.origin(of: range.start.file) == .user,
                  context.interner.resolve(name) == "appendLine"
            else { continue }
            calls += 1
            let binding = try #require(sema.bindings.callBinding(for: expression))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: symbol.id))
            let argument = try #require(arguments.first)
            let argumentType = try #require(sema.bindings.exprTypes[argument.expr])
            #expect(signature.parameterTypes == [argumentType])
            #expect(signature.returnType == sema.bindings.exprTypes[receiver])
            #expect(symbol.flags.contains(.inlineFunction))
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.externalLinkName(for: symbol.id) == nil)
            let file = try #require(sema.symbols.sourceFileID(for: symbol.id))
            #expect(context.sourceManager.path(of: file) == "__bundled_kotlin/text/StringBuilder.kt")
        }
        #expect(calls == 11)
    }

    @Test
    func privateUserIndexedValueDoesNotChangeBundledConstructorResolution() throws {
        let context = makeContextFromSource("""
        private class IndexedValue
        fun create() = IndexedValue()
        """)
        try runSema(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map(\.message))")
    }
}
