@testable import CompilerCore
import Foundation
import Testing

/// KSP-1391: CharSequence.random-family is provided by bundled Kotlin source.
@Suite
struct CharSequenceRandomSourceMigrationTests {
    @Test
    func randomFamilyResolvesToBundledSourceForStringAndCharSequence() throws {
        let source = """
        import kotlin.random.Random

        fun randomOnCharSequence(value: CharSequence, random: Random): Char {
            val defaultValue = value.random()
            val seededValue = value.random(random)
            return if (defaultValue == seededValue) defaultValue else seededValue
        }

        fun randomOrNullOnCharSequence(value: CharSequence, random: Random): Char? {
            val defaultValue = value.randomOrNull()
            val seededValue = value.randomOrNull(random)
            return if (defaultValue != null) defaultValue else seededValue
        }

        fun randomOnString(): Char = "abc".random()
        fun randomOnStringSeeded(random: Random): Char = "abc".random(random)
        fun randomOrNullOnString(): Char? = "abc".randomOrNull()
        fun randomOrNullOnStringSeeded(random: Random): Char? = "abc".randomOrNull(random)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected random-family calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let interner = ctx.interner
            let randomNames = Set(["random", "randomOrNull"])
            let sourceSymbols = Set(
                ["random", "randomOrNull"].flatMap { name in
                    sema.symbols.lookupAll(fqName: ["kotlin", "text", name].map(interner.intern))
                }.filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID),
                          ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/text/StringHOF.kt"
                    else {
                        return false
                    }
                    return sema.symbols.externalLinkName(for: symbolID) == nil
                }
            )
            #expect(sourceSymbols.count == 4)

            var chosenCallees: [SymbolID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                      randomNames.contains(interner.resolve(callee)),
                      let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee
                else {
                    continue
                }
                chosenCallees.append(chosen)
            }

            #expect(chosenCallees.count == 8)
            #expect(chosenCallees.allSatisfy { sourceSymbols.contains($0) })
        }
    }
}
