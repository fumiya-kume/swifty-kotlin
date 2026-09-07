#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CharArrayConstructorSourceMigrationTests {
    @Test
    func charArrayInitializerIsBundledSourceBacked() throws {
        let ctx = makeContextFromSource(
            "fun make(size: Int): CharArray = CharArray(size) { Char(it + 65) }"
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "CharArray initializer should type-check")
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "CharArray"].map(ctx.interner.intern)
        let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: symbolID)
            else {
                return false
            }
            return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/CharArray/Stdlib.kt"
        }

        let initializerSymbols = sourceSymbols.filter {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.count == 2
        }
        #expect(initializerSymbols.count == 1, "Expected one bundled CharArray initializer overload")
        let symbol = try #require(initializerSymbols.first)
        let signature = try #require(sema.symbols.functionSignature(for: symbol))

        #expect(signature.receiverType == nil)
        #expect(signature.parameterTypes.first == sema.types.intType)
        #expect(sema.symbols.isSourceBackedSymbol(symbol))
        #expect(sema.symbols.externalLinkName(for: symbol) == nil)
        #expect(sema.symbols.symbol(symbol)?.flags.contains(.inlineFunction) == true)
    }
}
#endif
