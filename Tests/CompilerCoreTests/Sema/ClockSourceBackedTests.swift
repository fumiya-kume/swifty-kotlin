#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1481: `Clock.now` is a bundled-source interface member with its
/// runtime bridge retained for compiler-created time-source clock objects.
@Suite
struct ClockSourceBackedTests {
    @Test
    func clockNowIsSourceBackedAndBridgeLinked() throws {
        let source = """
        import kotlin.time.Clock
        import kotlin.time.Instant

        class FixedClock : Clock {
            override fun now(): Instant = Instant.fromEpochMilliseconds(1234L)
        }

        fun readClock(clock: Clock): Instant = clock.now()
        """
        let ctx = makeContextFromSource(source, emit: .executable)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected Clock diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let clockNowFQName = ["kotlin", "time", "Clock", "now"].map(interner.intern)
        let nowSymbols = sema.symbols.lookupAll(fqName: clockNowFQName)
        #expect(nowSymbols.count == 1, "Expected one source-backed Clock.now declaration")
        let nowSymbol = try #require(nowSymbols.first)
        let nowInfo = try #require(sema.symbols.symbol(nowSymbol))
        #expect(nowInfo.kind == .function)
        #expect(!nowInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(nowSymbol))
        #expect(sema.symbols.externalLinkName(for: nowSymbol) == "kk_clock_now")

        let clockSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "time", "Clock"].map(interner.intern)))
        let instantSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "time", "Instant"].map(interner.intern)))
        let clockType = sema.types.make(.classType(ClassType(
            classSymbol: clockSymbol,
            args: [],
            nullability: .nonNull
        )))
        let instantType = sema.types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let signature = try #require(sema.symbols.functionSignature(for: nowSymbol))
        #expect(signature.receiverType == clockType)
        #expect(signature.parameterTypes.isEmpty)
        #expect(signature.returnType == instantType)
    }
}
#endif
