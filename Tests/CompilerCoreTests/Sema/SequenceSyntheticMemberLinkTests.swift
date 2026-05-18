@testable import CompilerCore
import Foundation
import XCTest

final class SequenceSyntheticMemberLinkTests: XCTestCase {
    func testSequenceFilterIsInstanceResolvesInCallExpressions() throws {
        let source = """
        fun intsOnly(): Sequence<Int> {
            val values: Sequence<Any> = sequenceOf(1, "two", 3)
            return values.filterIsInstance<Int>()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.filterIsInstance surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "filterIsInstance"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_filterIsInstance"))
        }
    }

    func testSequenceFirstNotNullOfResolvesInCallExpressions() throws {
        let source = """
        fun pickLabel(): String {
            val values = sequenceOf(1, 2, 3)
            return values.firstNotNullOf<String> { value ->
                if (value == 2) "two" else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.firstNotNullOf surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "firstNotNullOf"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_firstNotNullOf"))
        }
    }

    func testSequenceFirstNotNullOfOrNullResolvesInCallExpressions() throws {
        let source = """
        fun pickLabel(): String? {
            val values = sequenceOf(1, 2, 3)
            return values.firstNotNullOfOrNull<String> { value ->
                if (value == 2) "two" else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.firstNotNullOfOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "firstNotNullOfOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_firstNotNullOfOrNull"))
        }
    }

    func testSequenceMinusElementResolvesInCallExpressions() throws {
        let source = """
        fun removeValue(): Sequence<Int> {
            val values = sequenceOf(1, 2, 3)
            return values.minusElement(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.minusElement surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "minusElement"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_minus"))
        }
    }

    func testSequenceToSortedSetResolvesInCallExpressions() throws {
        let source = """
        fun collectSortedValues(): MutableSet<Int> {
            val values = sequenceOf(3, 1, 2, 1)
            return values.toSortedSet()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.toSortedSet surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "toSortedSet"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_toSortedSet"))
        }
    }

    func testSequenceChunkedResolvesInCallExpressions() throws {
        let source = """
        fun chunkValues(): Int {
            val values = sequenceOf(1, 2, 3, 4, 5)
            val chunks = values.chunked(2)
            return chunks.toList().size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.chunked surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "chunked"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_chunked"))
        }
    }

    func testSequenceSumByResolvesInCallExpressions() throws {
        let source = """
        fun weighted(): Int {
            val values = sequenceOf(1, 2, 3)
            return values.sumBy { value ->
                if (value == 2) 10 else value
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.sumBy surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "sumBy"]
                .map { ctx.interner.intern($0) }
            let sumBySymbols = sema.symbols.lookupAll(fqName: memberFQName)
            let links = Set(sumBySymbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertTrue(links.contains("kk_sequence_sumBy"))
            let sumBySymbol = try XCTUnwrap(sumBySymbols.first)
            XCTAssertTrue(
                sema.symbols.annotations(for: sumBySymbol).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "Sequence.sumBy should carry Deprecated metadata"
            )
        }
    }

    func testSequenceSumByDoubleResolvesInCallExpressions() throws {
        let source = """
        fun weighted(): Double {
            val values = sequenceOf(1, 2, 3)
            return values.sumByDouble { value ->
                if (value == 2) 1.5 else 0.25
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.sumByDouble surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "sumByDouble"]
                .map { ctx.interner.intern($0) }
            let sumByDoubleSymbols = sema.symbols.lookupAll(fqName: memberFQName)
            let links = Set(sumByDoubleSymbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertTrue(links.contains("kk_sequence_sumByDouble"))
            let sumByDoubleSymbol = try XCTUnwrap(sumByDoubleSymbols.first)
            XCTAssertTrue(
                sema.symbols.annotations(for: sumByDoubleSymbol).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "Sequence.sumByDouble should carry Deprecated metadata"
            )
        }
    }

    func testSequenceFilterNotToResolvesInCallExpressions() throws {
        let source = """
        fun odds(): MutableList<Int> {
            val values = sequenceOf(1, 2, 3, 4, 5)
            val destination = mutableListOf<Int>(99)
            return values.filterNotTo(destination) { value -> value % 2 == 0 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Sequence.filterNotTo surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "filterNotTo"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_filterNotTo"))
        }
    }
}
