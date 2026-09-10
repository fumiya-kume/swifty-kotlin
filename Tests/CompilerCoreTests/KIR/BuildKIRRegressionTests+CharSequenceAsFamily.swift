#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testCharSequenceAsFamilyRemainsSourceBacked() throws {
        let source = """
        fun iterable(value: CharSequence): Iterable<Char> = value.asIterable()
        fun sequence(value: CharSequence): Sequence<Char> = value.asSequence()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            for (functionName, apiName) in [("iterable", "asIterable"), ("sequence", "asSequence")] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                let call = try #require(body.compactMap { instruction -> (SymbolID?, String)? in
                    guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else {
                        return nil
                    }
                    return (symbol, ctx.interner.resolve(callee))
                }.first { $0.1 == apiName })
                let symbol = try #require(call.0)
                let declaration = try #require(sema.symbols.symbol(symbol))

                #expect(sema.symbols.isSourceBackedSymbol(symbol))
                #expect(sema.symbols.externalLinkName(for: symbol) == nil)
                #expect(declaration.fqName == [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("text"),
                    ctx.interner.intern(apiName),
                ])
            }

            var allCallees: [String] = []
            for functionName in ["iterable", "sequence"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                allCallees.append(contentsOf: extractCallees(from: body, interner: ctx.interner))
            }
            #expect(!allCallees.contains("kk_string_asIterable"))
            #expect(!allCallees.contains("kk_string_asIterable_flat"))
            #expect(!allCallees.contains("kk_string_asSequence"))
            #expect(!allCallees.contains("kk_string_asSequence_flat"))
        }
    }
}
#endif
