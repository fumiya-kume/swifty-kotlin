@testable import CompilerCore
import Foundation
import XCTest

final class SequenceSortedByFunctionTests: XCTestCase {
    func testSequenceSortedByResolvesToRuntimeABIAndPreservesSequenceResult() throws {
        let source = """
        fun probe(values: Sequence<String>): Sequence<String> {
            return values.sortedBy { value -> value.length }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected Sequence.sortedBy to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let memberFQName = [
                "kotlin", "sequences", "Sequence", "sortedBy",
            ].map(ctx.interner.intern)
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)

            XCTAssertTrue(
                sequenceMembers.contains { sema.symbols.externalLinkName(for: $0) == "kk_sequence_sortedBy" },
                "Expected Sequence.sortedBy synthetic member to link to kk_sequence_sortedBy"
            )

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "sortedBy"
            }, "Expected sortedBy member call")

            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_sequence_sortedBy",
                "Expected sortedBy call site to resolve to kk_sequence_sortedBy runtime"
            )

            // The probe() function's declared return type should be Sequence<String>.
            let probeSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [ctx.interner.intern("probe")]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: probeSymbol))
            let sequenceSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: ["kotlin", "sequences", "Sequence"].map { ctx.interner.intern($0) }
            ))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected probe() to return Sequence<String>")
            }
            XCTAssertEqual(returnClassType.classSymbol, sequenceSymbol)
            let returnArg: TypeID
            switch try XCTUnwrap(returnClassType.args.first) {
            case let .invariant(arg), let .out(arg):
                returnArg = arg
            case .in, .star:
                return XCTFail("Expected probe() to return Sequence<String>")
            }
            XCTAssertEqual(returnArg, sema.types.stringType)
        }
    }
}
