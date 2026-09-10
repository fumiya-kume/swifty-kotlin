#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ULongProgressionHOFSourceMigrationTests {
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
                interner.intern("ULongProgression"),
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
                    "Expected one source-backed ULongProgression.\(memberName)(), got: \(sourceSymbols)"
                )
                if let sourceSymbol = sourceSymbols.first,
                   let signature = sema.symbols.functionSignature(for: sourceSymbol)
                {
                    let expectedReturn = memberName.hasSuffix("OrNull")
                        ? sema.types.makeNullable(sema.types.ulongType)
                        : sema.types.ulongType
                    #expect(signature.returnType == expectedReturn)
                }
            }
        }
    }

    @Test
    func noArgumentCallsBindToSourceDefinitions() throws {
        let source = """
        fun probe(progression: ULongProgression) {
            progression.first()
            progression.firstOrNull()
            progression.last()
            progression.lastOrNull()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected ULongProgression first-family calls to type-check: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedReceiver = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ranges"),
                ctx.interner.intern("ULongProgression"),
            ]
            var seen = Set<String>()
            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard case let .memberCall(callReceiver, callee, _, _, _) = ast.arena.expr(exprID),
                      let receiverType = sema.bindings.exprType(for: callReceiver),
                      let (_, callReceiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
                      callReceiverSymbol.fqName == expectedReceiver
                else { continue }
                let memberName = ctx.interner.resolve(callee)
                guard ["first", "firstOrNull", "last", "lastOrNull"].contains(memberName),
                      let binding = sema.bindings.callBinding(for: exprID)
                else { continue }
                let chosen = binding.chosenCallee
                #expect(sema.symbols.isSourceBackedSymbol(chosen))
                #expect(sema.symbols.externalLinkName(for: chosen) == nil)
                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(signature.parameterTypes.isEmpty)
                let expectedReturn = memberName.hasSuffix("OrNull")
                    ? sema.types.makeNullable(sema.types.ulongType)
                    : sema.types.ulongType
                #expect(
                    signature.returnType == expectedReturn,
                    "Unexpected ULongProgression.\(memberName)() return type for \(chosen): \(signature.returnType)"
                )
                let receiver = try #require(signature.receiverType)
                let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiver, sema: sema))
                #expect(
                    receiverSymbol.fqName == [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("ranges"),
                        ctx.interner.intern("ULongProgression"),
                    ],
                    "Unexpected ULongProgression.\(memberName)() receiver for \(chosen): \(receiverSymbol.fqName.map(ctx.interner.resolve))"
                )
                seen.insert(ctx.interner.resolve(callee))
            }
            #expect(seen == ["first", "firstOrNull", "last", "lastOrNull"])
        }
    }

    @Test
    func localExtensionRemainsPreferredForSameReceiver() throws {
        let source = """
        fun ULongProgression.last(): ULong {
            return 99uL
        }

        fun probe(progression: ULongProgression) {
            progression.last()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected the local ULongProgression.last() extension to type-check: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedReceiver = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ranges"),
                ctx.interner.intern("ULongProgression"),
            ]
            var matchingCalls = 0
            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard case let .memberCall(callReceiver, callee, _, _, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(callee) == "last",
                      let receiverType = sema.bindings.exprType(for: callReceiver),
                      let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
                      receiverSymbol.fqName == expectedReceiver,
                      let binding = sema.bindings.callBinding(for: exprID),
                      let chosenSymbol = sema.symbols.symbol(binding.chosenCallee),
                      let chosenSourceFileID = sema.symbols.sourceFileID(for: binding.chosenCallee)
                else { continue }
                matchingCalls += 1
                #expect(ctx.sourceManager.path(of: chosenSourceFileID) == path)
                #expect(chosenSymbol.fqName.last == ctx.interner.intern("last"))
            }
            #expect(matchingCalls == 1)
        }
    }
}
#endif
