#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testCharArrayLambdaConstructorLowersToArrayNewAndArraySet() throws {
        let source = """
        fun make(size: Int): CharArray = CharArray(size) { Char(it + 65) }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callNames.contains("kk_array_new_checked"),
                "CharArray(n) { init } must emit checked primitive-array allocation; got: \(callNames)"
            )
            #expect(
                callNames.contains("kk_array_set"),
                "CharArray(n) { init } must emit primitive-array stores; got: \(callNames)"
            )
            #expect(
                !callNames.contains("CharArray"),
                "CharArray initializer must be inlined rather than left as a call; got: \(callNames)"
            )
            #expect(
                !callNames.contains("kk_box_char"),
                "CharArray initializer must keep Char elements unboxed; got: \(callNames)"
            )
        }
    }
}
#endif
