#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1481: calls through `Clock` must remain interface dispatch after the
/// source-backed declaration replaces the synthetic member.
@Suite
struct ClockNowKIRRegressionTests {
    @Test
    func clockNowLowersToItableVirtualCall() throws {
        let source = """
        import kotlin.time.Clock
        import kotlin.time.Instant

        class FixedClock : Clock {
            override fun now(): Instant = Instant.fromEpochMilliseconds(1234L)
        }

        fun readClock(clock: Clock): Instant = clock.now()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                emit: .kirDump,
                allowDefaultStdlibLibrary: false
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "readClock", in: module, interner: ctx.interner)
            let virtualCalls = body.compactMap { instruction -> (InternedString, KIRDispatchKind)? in
                guard case let .virtualCall(_, callee, _, _, _, _, _, dispatch) = instruction else {
                    return nil
                }
                return (callee, dispatch)
            }
            let clockCall = try #require(virtualCalls.first { ctx.interner.resolve($0.0) == "kk_clock_now" })
            guard case let .itableDynamic(_, methodSlot) = clockCall.1 else {
                Issue.record("Expected Clock.now to use dynamic itable dispatch, got \(clockCall.1)")
                return
            }
            #expect(methodSlot == 0)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected Clock KIR diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
