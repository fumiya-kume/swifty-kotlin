#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-848: preserve the shared checked allocation and primitive-element store
/// lowering for FloatArray constructors without adding a FloatArray-specific ABI.
@Suite
struct FloatArrayConstructorLoweringTests {
    @Test
    func constructorsLowerToSharedArrayRuntimeCalls() throws {
        let ctx = makeContextFromSource("""
        fun initialize(): FloatArray = FloatArray(4) { index ->
            if (index == 0) 1.5f else 2.5f
        }
        fun allocate(): FloatArray = FloatArray(3)
        """, emit: .kirDump)
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)

        let module = try #require(ctx.kir)
        let initializedBody = try findKIRFunctionBody(named: "initialize", in: module, interner: ctx.interner)
        let initializedCallees = extractCallees(from: initializedBody, interner: ctx.interner)
        #expect(initializedCallees.contains("kk_array_new_checked"))
        #expect(initializedCallees.contains("kk_array_set"))
        #expect(!initializedCallees.contains("FloatArray"))

        let initializedThrows = extractThrowFlags(from: initializedBody, interner: ctx.interner)
        #expect(initializedThrows["kk_array_new_checked"]?.allSatisfy { $0 } == true)

        let sizeOnlyBody = try findKIRFunctionBody(named: "allocate", in: module, interner: ctx.interner)
        let sizeOnlyCallees = extractCallees(from: sizeOnlyBody, interner: ctx.interner)
        #expect(sizeOnlyCallees.contains("kk_array_new_checked"))
        #expect(!sizeOnlyCallees.contains("kk_array_set"))
        #expect(!sizeOnlyCallees.contains("FloatArray"))
    }
}
#endif
