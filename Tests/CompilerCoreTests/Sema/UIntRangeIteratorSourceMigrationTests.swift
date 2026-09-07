#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct UIntRangeIteratorSourceMigrationTests {
    private struct ExpectedMember {
        let owner: String
        let name: String
        let parameterCount: Int
        let sourceFile: String
    }

    private let migratedMembers = [
        ExpectedMember(owner: "UIntRange", name: "iterator", parameterCount: 0, sourceFile: "RangeIterators.kt"),
        ExpectedMember(owner: "UIntProgression", name: "iterator", parameterCount: 0, sourceFile: "RangeIterators.kt"),
        ExpectedMember(owner: "UIntRange", name: "step", parameterCount: 1, sourceFile: "ProgressionConstructors.kt"),
        ExpectedMember(owner: "UIntProgression", name: "step", parameterCount: 1, sourceFile: "ProgressionConstructors.kt"),
        ExpectedMember(owner: "UIntRange", name: "take", parameterCount: 1, sourceFile: "RangeHOF.kt"),
        ExpectedMember(owner: "UIntRange", name: "drop", parameterCount: 1, sourceFile: "RangeHOF.kt"),
        ExpectedMember(owner: "UIntRange", name: "chunked", parameterCount: 1, sourceFile: "RangeHOF.kt"),
        ExpectedMember(owner: "UIntRange", name: "windowed", parameterCount: 3, sourceFile: "RangeHOF.kt"),
        ExpectedMember(owner: "UIntProgression", name: "take", parameterCount: 1, sourceFile: "RangeHOF.kt"),
        ExpectedMember(owner: "UIntProgression", name: "drop", parameterCount: 1, sourceFile: "RangeHOF.kt"),
        ExpectedMember(owner: "UIntProgression", name: "chunked", parameterCount: 1, sourceFile: "RangeHOF.kt"),
        ExpectedMember(owner: "UIntProgression", name: "windowed", parameterCount: 3, sourceFile: "RangeHOF.kt"),
    ]

    @Test
    func migratedMembersAreUIntSourceDefinitions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for expected in migratedMembers {
                let fqName = ["kotlin", "ranges", expected.name].map(interner.intern)
                let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          sema.symbols.isSourceBackedSymbol(symbolID),
                          sema.symbols.externalLinkName(for: symbolID) == nil,
                          let sourceFileID = sema.symbols.sourceFileID(for: symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.count == expected.parameterCount,
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                          let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                    else {
                        return false
                    }
                    guard ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/ranges/\(expected.sourceFile)"
                    else {
                        return false
                    }
                    return interner.resolve(receiverSymbol.name) == expected.owner
                }

                #expect(
                    sourceSymbols.count == 1,
                    "Expected one source-backed UInt\(expected.owner).\(expected.name), got: \(sourceSymbols)"
                )
            }
        }
    }

    @Test
    func UIntRangeCallsBindToSourceDefinitions() throws {
        let source = """
        fun rangeToValue(): UIntRange = 1u.rangeTo(5u)
        fun rangeOperatorValue(): UIntRange = 1u..5u
        fun rangeStep(range: UIntRange): UIntProgression = range.step(2)
        fun progressionStep(progression: UIntProgression): UIntProgression = progression.step(2)
        fun rangeIterator(range: UIntRange): Iterator<UInt> = range.iterator()
        fun progressionIterator(progression: UIntProgression): Iterator<UInt> = progression.iterator()
        fun rangeTake(range: UIntRange): List<UInt> = range.take(2)
        fun rangeDrop(range: UIntRange): List<UInt> = range.drop(2)
        fun rangeChunked(range: UIntRange): List<List<UInt>> = range.chunked(2)
        fun rangeWindowed(range: UIntRange): List<List<UInt>> = range.windowed(2)
        fun progressionTake(progression: UIntProgression): List<UInt> = progression.take(2)
        fun progressionDrop(progression: UIntProgression): List<UInt> = progression.drop(2)
        fun progressionChunked(progression: UIntProgression): List<List<UInt>> = progression.chunked(2)
        fun progressionWindowed(progression: UIntProgression): List<List<UInt>> = progression.windowed(2, 2, true)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected UInt range migration calls to type-check: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedNames = Set(["rangeTo", "step", "iterator", "take", "drop", "chunked", "windowed"])
            var seen = Set<String>()
            var rangeOperatorSeen = false

            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let exprRange = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: exprRange.start.file) == path
                else {
                    continue
                }
                if case let .binary(op, _, _, _) = ast.arena.expr(exprID), op == .rangeTo {
                    let chosenCallee = try #require(sema.bindings.callBinding(for: exprID)?.chosenCallee)
                    #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected UInt rangeTo operator to be source-backed")
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                    rangeOperatorSeen = true
                    continue
                }
                guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID) else {
                    continue
                }
                let memberName = ctx.interner.resolve(callee)
                guard expectedNames.contains(memberName) else { continue }
                let chosenCallee = try #require(sema.bindings.callBinding(for: exprID)?.chosenCallee)
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected UIntRange/UIntProgression.\(memberName) to be source-backed")
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                seen.insert(memberName)
            }

            #expect(seen == expectedNames, "Missing source-backed UInt migration calls: \(expectedNames.subtracting(seen))")
            #expect(rangeOperatorSeen, "Missing source-backed UInt rangeTo operator")
        }
    }
}
#endif
