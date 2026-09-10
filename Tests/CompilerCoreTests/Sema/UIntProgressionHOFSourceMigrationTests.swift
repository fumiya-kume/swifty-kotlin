#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct UIntProgressionHOFSourceMigrationTests {
    @Test
    func noArgumentFirstFamilyAreSourceDefinitions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let expectedReceiver = [
                interner.intern("kotlin"),
                interner.intern("ranges"),
                interner.intern("UIntProgression"),
            ]

            for memberName in ["first", "firstOrNull", "last", "lastOrNull"] {
                let sourceSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("ranges"),
                    interner.intern(memberName),
                ]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let sourceFileID = sema.symbols.sourceFileID(for: symbolID),
                          ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/ranges/RangeHOF.kt",
                          sema.symbols.externalLinkName(for: symbolID) == nil,
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.isEmpty,
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                          let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                    else {
                        return false
                    }
                    return receiverSymbol.fqName == expectedReceiver
                }

                #expect(
                    sourceSymbols.count == 1,
                    "Expected one source-backed UIntProgression.\(memberName)(), got: \(sourceSymbols)"
                )
                if let sourceSymbol = sourceSymbols.first,
                   let signature = sema.symbols.functionSignature(for: sourceSymbol)
                {
                    let expectedReturn = memberName.hasSuffix("OrNull")
                        ? sema.types.makeNullable(sema.types.uintType)
                        : sema.types.uintType
                    #expect(signature.returnType == expectedReturn)
                }
            }
        }
    }

    @Test
    func noArgumentCallsBindToSourceDefinitionsAndKeepPropertiesSeparate() throws {
        let source = """
        fun probe() {
            val positive = UIntProgression.fromClosedRange(2u, 11u, 3)
            val negative = 10u downTo 1u step 3
            val propertyValues = positive.first + positive.last
            positive.first()
            positive.firstOrNull()
            positive.last()
            positive.lastOrNull()
            negative.first()
            negative.firstOrNull()
            negative.last()
            negative.lastOrNull()
            propertyValues
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected UIntProgression first-family calls to type-check: \(ctx.diagnostics.diagnostics)")
            let progressionOverlapWarnings = ctx.diagnostics.diagnostics.filter { diagnostic in
                diagnostic.code == "KSWIFTK-SEMA-0102"
                    && diagnostic.message.contains("UIntProgression")
                    && (["first", "firstOrNull", "last", "lastOrNull"].contains { memberName in
                        diagnostic.message.contains("'\(memberName)'")
                    })
            }
            #expect(
                progressionOverlapWarnings.isEmpty,
                "Expected retained UIntProgression properties to avoid duplicate source-function warnings: \(progressionOverlapWarnings)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var seen = Set<String>()
            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID)
                else { continue }
                let memberName = ctx.interner.resolve(callee)
                guard ["first", "firstOrNull", "last", "lastOrNull"].contains(memberName),
                      let binding = sema.bindings.callBinding(for: exprID)
                else { continue }

                let chosen = binding.chosenCallee
                #expect(sema.symbols.isSourceBackedSymbol(chosen), "Expected UIntProgression.\(memberName)() to be source-backed")
                #expect(sema.symbols.externalLinkName(for: chosen) == nil)
                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(signature.parameterTypes.isEmpty)
                let receiver = try #require(signature.receiverType)
                let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiver, sema: sema))
                #expect(
                    receiverSymbol.fqName == [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("ranges"),
                        ctx.interner.intern("UIntProgression"),
                    ],
                    "Unexpected receiver for UIntProgression.\(memberName)()"
                )
                seen.insert(memberName)
            }

            #expect(seen == ["first", "firstOrNull", "last", "lastOrNull"], "Missing source-backed calls: \(seen)")
        }
    }
}
#endif
