@testable import CompilerCore
import Foundation
import XCTest

final class SequenceSyntheticMemberLinkTests: XCTestCase {
    func testSequenceFilterIndexedTypeChecksInCallExpressions() throws {
        let source = """
        fun indexedValues(): Sequence<Int> {
            val values = sequenceOf(10, 20, 30)
            return values.filterIndexed { index, value -> index == 1 || value == 30 }
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
                "Expected Sequence.filterIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

        }
    }

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

    func testSequenceTakeLastResolvesInCallExpressions() throws {
        let source = """
        fun lastTwo(): List<Int> {
            val values = sequenceOf(1, 2, 3)
            return values.takeLast(2)
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
                "Expected Sequence.takeLast surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "takeLast"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_takeLast"))
        }
    }

    func testSequenceSingleOrNullResolvesInCallExpressions() throws {
        let source = """
        fun pickOnly(): Int? {
            return sequenceOf(42).singleOrNull()
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
                "Expected Sequence.singleOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "singleOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_singleOrNull"))
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

    func testSequenceSumOfResolvesInCallExpressions() throws {
        let source = """
        fun weighted(): Int {
            val values = sequenceOf(1, 2, 3)
            return values.sumOf { value ->
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
                "Expected Sequence.sumOf surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "sumOf"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_sumOf"))
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

    func testSequenceWithIndexResolvesInCallExpressions() throws {
        let source = """
        fun indexedValuesSize(): Int {
            val values = sequenceOf(10, 20, 30)
            return values.withIndex().toList().size
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
                "Expected Sequence.withIndex surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "withIndex"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_withIndex"))

            let withIndexSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            let indexedValueSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("IndexedValue"),
            ]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: withIndexSymbol))
            guard case let .classType(sequenceType) = sema.types.kind(of: signature.returnType),
                  let firstArg = sequenceType.args.first,
                  case let .out(elementType) = firstArg,
                  case let .classType(indexedValueType) = sema.types.kind(of: elementType)
            else {
                return XCTFail("Expected Sequence.withIndex() to return Sequence<IndexedValue<T>>")
            }
            XCTAssertEqual(indexedValueType.classSymbol, indexedValueSymbol)
        }
    }

    func testSequenceMinusResolvesInCallExpressions() throws {
        let source = """
        fun removeValue(): Sequence<Int> {
            val values = sequenceOf(1, 2, 3)
            return values.minus(2)
        }

        fun removeWithOperator(): Sequence<Int> {
            val values = sequenceOf(1, 2, 3)
            return values - 2
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
                "Expected Sequence.minus surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "minus"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_minus"))
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

    func testSequenceSumOfResolvesInCallExpressions() throws {
        let source = """
        fun weighted(): Int {
            val values = sequenceOf(1, 2, 3)
            return values.sumOf { value ->
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
                "Expected Sequence.sumOf surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "sumOf"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_sumOf"))
        }
    }

    func testSequenceSumResolvesInCallExpressions() throws {
        let source = """
        fun total(): Int {
            val values = sequenceOf(1, 2, 3)
            return values.sum()
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
                "Expected Sequence.sum surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "sum"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_sum"))
        }
    }

    func testSequenceAverageOfResolvesInCallExpressions() throws {
        let source = """
        fun averageLengths(): Double {
            val values = sequenceOf("a", "bbb", "cc")
            return values.averageOf { value ->
                value.length
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
                "Expected Sequence.averageOf surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "averageOf"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_averageOf"))
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

    func testSequenceMaxOfOrNullResolvesInCallExpressions() throws {
        let source = """
        fun largestSelectorOrNull(): Int? {
            val values = sequenceOf(1, 3, 2)
            return values.maxOfOrNull { value -> -value }
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
                "Expected Sequence.maxOfOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "maxOfOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_maxOfOrNull"))
        }
    }

    func testSequenceMaxOrNullResolvesWithNullableElementReturnType() throws {
        let source = """
        fun largestOrNull(): Int? {
            val values = sequenceOf(1, 3, 2)
            return values.maxOrNull()
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
                "Expected Sequence.maxOrNull surface to resolve as T?, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "maxOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_maxOrNull"))
        }
    }

    func testSequenceFindResolvesInCallExpressions() throws {
        let source = """
        fun firstEven(): Int? {
            val values = sequenceOf(1, 2, 3, 4, 5)
            return values.find { value -> value % 2 == 0 }
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
                "Expected Sequence.find surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "find"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_find"))
        }
    }

    func testSequenceMaxWithOrNullResolvesInCallExpressions() throws {
        let source = """
        fun largestOrNull(): Int? {
            val values = sequenceOf(1, 3, 2)
            return values.maxWithOrNull { left, right -> left - right }
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
                "Expected Sequence.maxWithOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "maxWithOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_maxWithOrNull"))
        }
    }

    func testSequenceFilterNotResolvesInCallExpressions() throws {
        let source = """
        fun odds(): Sequence<Int> {
            val values = sequenceOf(1, 2, 3, 4, 5)
            return values.filterNot { value -> value % 2 == 0 }
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
                "Expected Sequence.filterNot surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "filterNot"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_filterNot"))
        }
    }

    func testSequenceFilterIsInstanceToResolvesInCallExpressions() throws {
        let source = """
        fun collectInts(): MutableList<Int> {
            val values: Sequence<Any> = sequenceOf(1, "two", 3)
            val dest = mutableListOf<Int>(0)
            return values.filterIsInstanceTo(dest)
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
                "Expected Sequence.filterIsInstanceTo surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIsInstanceTo"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected Sequence.filterIsInstanceTo to bind to its synthetic runtime callee"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_sequence_filterIsInstanceTo")
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(callExpr),
                "Expected filterIsInstanceTo result to be tracked as a collection expression"
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

    func testSequenceRunningReduceIndexedResolvesInCallExpressions() throws {
        let source = """
        fun indexedTotals() {
            val totals = sequenceOf(1, 2, 3).runningReduceIndexed { index, acc, value ->
                acc + index + value
            }
            println(totals)
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
                "Expected Sequence.runningReduceIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "runningReduceIndexed"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_runningReduceIndexed"))
        }
    }

    func testSequenceMaxOfResolvesInCallExpressions() throws {
        let source = """
        fun largestSelector(): Int {
            val values = sequenceOf(1, 3, 2)
            return values.maxOf { value -> -value }
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
                "Expected Sequence.maxOf surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "maxOf"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_maxOf"))
        }
    }

    func testSequenceMinResolvesInCallExpressions() throws {
        let source = """
        fun smallest(): Int {
            val values = sequenceOf(3, 1, 2)
            return values.min()
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
                "Expected Sequence.min surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "min"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_min"))
        }
    }

    func testSequenceMaxResolvesInCallExpressions() throws {
        let source = """
        fun largest(): Int {
            val values = sequenceOf(1, 3, 2)
            return values.max()
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
                "Expected Sequence.max surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "max"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_max"))
        }
    }

    func testSequenceMinOfOrNullResolvesInCallExpressions() throws {
        let source = """
        fun smallestProjection(): Int? {
            val values = sequenceOf(5, 2, 3)
            return values.minOfOrNull { value -> value * 10 }
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
                "Expected Sequence.minOfOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "minOfOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_minOfOrNull"))
        }
    }

    func testSequenceScanIndexedResolvesInCallExpressions() throws {
        let source = """
        fun indexedScan() {
            sequenceOf(1, 2, 3).scanIndexed(10) { index, acc, value ->
                acc + index + value
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
                "Expected Sequence.scanIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "scanIndexed"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_scanIndexed"))
        }
    }

    func testSequenceReduceRightIndexedResolvesInCallExpressions() throws {
        let source = """
        fun checksum(): Int {
            val values = sequenceOf(1, 2, 3, 4)
            return values.reduceRightIndexed { index, value, acc -> index * 100 + value * 10 + acc }
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
                "Expected Sequence.reduceRightIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "reduceRightIndexed"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_reduceRightIndexed"))
        }
    }

    func testSequenceScanResolvesInCallExpressions() throws {
        let source = """
        fun scanned(): Sequence<Int> {
            return sequenceOf(1, 2, 3).scan(10) { acc, value ->
                acc + value
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
                "Expected Sequence.scan surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "scan"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_scan"))
        }
    }

    func testSequenceRequireNoNullsResolvesNullableReceiverInCallExpressions() throws {
        let source = """
        fun checked(values: Sequence<Int?>) {
            val result = values.requireNoNulls()
            println(result.toList())
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
                "Expected Sequence.requireNoNulls surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "requireNoNulls"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_requireNoNulls"))
        }
    }

    func testSequenceMaxByResolvesInCallExpressions() throws {
        let source = """
        fun largestByNegative(): Int {
            val values = sequenceOf(1, 3, 2)
            return values.maxBy { value -> -value }
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
                "Expected Sequence.maxBy surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "maxBy"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_maxBy"))
        }
    }


    func testSequenceMinWithResolvesInCallExpressions() throws {
        let source = """
        fun smallestByReverseOrder(): Int {
            val values = sequenceOf(5, 2, 3)
            return values.minWith(reverseOrder<Int>())
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
                "Expected Sequence.minWith surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "minWith"]
                .map { ctx.interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: memberFQName)
            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertTrue(links.contains("kk_sequence_minWith"))

            let symbol = try XCTUnwrap(symbols.first)
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.parameterTypes.count, 1)
        }
    }


    func testSequenceMaxByOrNullResolvesInCallExpressions() throws {
        let source = """
        fun largestByNegativeOrNull(): Int? {
            val values = sequenceOf(1, 3, 2)
            return values.maxByOrNull { value -> -value }
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
                "Expected Sequence.maxByOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "maxByOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_maxByOrNull"))
        }
    }

    func testSequenceMinByOrNullResolvesInCallExpressions() throws {
        let source = """
        fun smallestByRemainder(): Int? {
            val values = sequenceOf(5, 2, 3)
            return values.minByOrNull { value -> value % 3 }
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
                "Expected Sequence.minByOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "minByOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_minByOrNull"))
        }
    }
}
