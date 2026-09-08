#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func genericArrayConstructorsLowerToCheckedAllocation() throws {
        let sources = [
            """
            package genericarray
            fun initialized() = Array(3) { it * 2 }
            fun sized(): Array<String?> = Array(2)
            """
        ]
        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        let module = try #require(ctx.kir)

        let initializedBody = try findKIRFunctionBody(
            named: "initialized", in: module, interner: ctx.interner
        )
        let sizedBody = try findKIRFunctionBody(
            named: "sized", in: module, interner: ctx.interner
        )

        let initializedCallees = extractCallees(from: initializedBody, interner: ctx.interner)
        let sizedCallees = extractCallees(from: sizedBody, interner: ctx.interner)
        #expect(initializedCallees.contains("kk_array_new_checked"))
        #expect(initializedCallees.contains("kk_array_set"))
        #expect(sizedCallees == ["kk_array_new_checked"])

        let throwFlags = extractThrowFlags(from: sizedBody, interner: ctx.interner)
        #expect(throwFlags["kk_array_new_checked"]?.allSatisfy { $0 } == true)
    }
}
#endif
