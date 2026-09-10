#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func iterableCollectionSizeHelpersRemainBundledKotlinCalls() throws {
        let source = """
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        fun knownOrNull(values: Iterable<Int>): Int? = values.collectionSizeOrNull()

        fun knownOrDefault(values: Iterable<Int>): Int = values.collectionSizeOrDefault(23)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected collection-size helper KIR to build, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let cases = [
                (function: "knownOrNull", callee: "collectionSizeOrNull"),
                (function: "knownOrDefault", callee: "collectionSizeOrDefault"),
            ]
            for item in cases {
                let body = try findKIRFunctionBody(
                    named: item.function,
                    in: module,
                    interner: ctx.interner
                )
                let callees = Set(extractCallees(from: body, interner: ctx.interner))
                #expect(callees.contains(item.callee), "\(item.function): \(callees.sorted())")
                #expect(!callees.contains("kk_\(item.callee)"))
                #expect(!callees.contains("__kk_\(item.callee)"))
            }
        }
    }
}
#endif
