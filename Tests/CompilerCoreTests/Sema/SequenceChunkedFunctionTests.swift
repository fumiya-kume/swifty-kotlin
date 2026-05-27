@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-SEQ-FN-012: Validates that `Sequence<T>.chunked` resolves through Sema
/// for both overloads — the size-only form returning `Sequence<List<T>>` linked to
/// `kk_sequence_chunked`, and the size + transform form returning `Sequence<R>`
/// linked to `kk_sequence_chunked_transform`.
final class SequenceChunkedFunctionTests: XCTestCase {
    func testSequenceChunkedSizeOnlyOverloadResolvesToRuntimeABI() throws {
        let source = """
        fun probe(values: Sequence<Int>): Sequence<List<Int>> {
            return values.chunked(3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected Sequence.chunked(size) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = [
                "kotlin", "sequences", "Sequence", "chunked",
            ].map(ctx.interner.intern)
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)
            XCTAssertTrue(
                sequenceMembers.contains { sema.symbols.externalLinkName(for: $0) == "kk_sequence_chunked" },
                "Expected Sequence.chunked(size) synthetic member to link to kk_sequence_chunked"
            )
        }
    }

    func testSequenceChunkedSizeTransformOverloadResolvesToRuntimeABI() throws {
        let source = """
        fun probe(values: Sequence<Int>): Sequence<Int> {
            return values.chunked(3) { chunk -> chunk.size }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected Sequence.chunked(size, transform) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = [
                "kotlin", "sequences", "Sequence", "chunked",
            ].map(ctx.interner.intern)
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)
            XCTAssertTrue(
                sequenceMembers.contains {
                    sema.symbols.externalLinkName(for: $0) == "kk_sequence_chunked_transform"
                },
                "Expected Sequence.chunked(size, transform) synthetic member to link to kk_sequence_chunked_transform"
            )
        }
    }
}
