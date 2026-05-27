@testable import CompilerCore
import Foundation
import XCTest

extension SequenceSyntheticMemberLinkTests {
    /// Shared helper for the "Sequence synthetic member link" test pattern.
    ///
    /// Almost every test in `SequenceSyntheticMemberLinkTests.swift` follows
    /// the same 4-step script:
    ///   1. Compile a tiny Kotlin snippet exercising `sequenceOf(...).<member>(...)`.
    ///   2. Assert that Sema produces no errors.
    ///   3. Look up `kotlin.sequences.Sequence.<memberName>` in the symbol table.
    ///   4. Assert that the resolved `externalLinkName` matches the expected
    ///      `kk_sequence_<member>` runtime function.
    ///
    /// Repeating this 30-line block per test made the file 2700+ lines long
    /// and turned it into one of the worst merge-conflict hotspots in the
    /// repo (~27 conflicts/month). New tests should use this helper —
    /// they end up around 8-12 lines each instead of 30. The smaller body
    /// also means parallel 3-way merges of nearby test definitions are far
    /// more likely to succeed without manual intervention.
    ///
    /// Existing tests are not migrated in this PR (to keep the diff small
    /// and reviewable). Subsequent PRs may gradually convert them.
    ///
    /// - Parameters:
    ///   - source: The Kotlin snippet to compile. Must contain at least one
    ///     usage of `Sequence.<memberName>` so Sema records a resolution.
    ///   - memberName: The Sequence member function name as it appears in
    ///     `kotlin.sequences.Sequence` (e.g. `"filter"`, `"reversed"`).
    ///   - expectedLinkName: The runtime function the resolution should map
    ///     to, e.g. `"kk_sequence_filter"`.
    ///   - diagnosticContext: Short human-readable phrase included in the
    ///     assertion message, e.g. `"Sequence.filter"`.
    func assertSequenceMemberResolves(
        source: String,
        memberName: String,
        expectedLinkName: String,
        diagnosticContext: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected \(diagnosticContext) surface to resolve cleanly, " +
                    "got: \(diagnosticSummary)",
                file: file, line: line
            )

            let sema = try XCTUnwrap(ctx.sema, file: file, line: line)
            let memberFQName = ["kotlin", "sequences", "Sequence", memberName]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(
                links.contains(expectedLinkName),
                "Expected '\(expectedLinkName)' in resolved link names " +
                    "\(links.sorted()) for \(diagnosticContext)",
                file: file, line: line
            )
        }
    }
}
