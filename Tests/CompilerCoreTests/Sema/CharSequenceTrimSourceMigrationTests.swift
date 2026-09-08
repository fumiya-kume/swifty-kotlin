@testable import CompilerCore
import Testing

@Suite
struct CharSequenceTrimSourceMigrationTests {
    @Test
    func allOverloadsBindToCharSequenceSourceWithExactReturnTypes() throws {
        let context = makeContextFromSource("""
        fun trims(source: CharSequence, predicate: (Char) -> Boolean) {
            val a: CharSequence = source.trim()
            val b: CharSequence = source.trim('x')
            val c: CharSequence = source.trim(predicate)
            val d: CharSequence = source.trimStart()
            val e: CharSequence = source.trimStart('x')
            val f: CharSequence = source.trimStart(predicate)
            val g: CharSequence = source.trimEnd()
            val h: CharSequence = source.trimEnd('x')
            val i: CharSequence = source.trimEnd(predicate)
        }
        """)
        try runSema(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map(\.message))")
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        var callees = Set<SymbolID>()
        for index in ast.arena.exprs.indices {
            let expression = ExprID(rawValue: Int32(index))
            guard case let .memberCall(receiver, name, _, _, range) = ast.arena.expr(expression),
                  context.sourceManager.origin(of: range.start.file) == .user,
                  ["trim", "trimStart", "trimEnd"].contains(context.interner.resolve(name))
            else { continue }
            let binding = try #require(sema.bindings.callBinding(for: expression))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: symbol.id))
            #expect(signature.receiverType == sema.bindings.exprTypes[receiver])
            #expect(signature.returnType == signature.receiverType)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.externalLinkName(for: symbol.id) == nil)
            let file = try #require(sema.symbols.sourceFileID(for: symbol.id))
            #expect(context.sourceManager.path(of: file) == "__bundled_kotlin/text/StringSliceTrim.kt")
            let takesPredicate = signature.parameterTypes.contains { parameter in
                if case .functionType = sema.types.kind(of: parameter) { return true }
                return false
            }
            #expect(symbol.flags.contains(.inlineFunction) == takesPredicate)
            callees.insert(symbol.id)
        }
        #expect(callees.count == 9)
    }

    @Test
    func existingStringCallsKeepStringReturnType() throws {
        let context = makeContextFromSource("""
        fun existing(source: String) {
            val a: String = source.trim()
            val b: String = source.trim { it == 'x' }
            val c: String = source.trimStart()
            val d: String = source.trimStart { it == 'x' }
            val e: String = source.trimEnd()
            val f: String = source.trimEnd { it == 'x' }
        }
        """)
        try runSema(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map(\.message))")
    }
}
