@testable import CompilerCore
import Foundation
import XCTest

final class SequenceSyntheticMemberLinkTests: XCTestCase {
    func testSequenceReduceIndexedResolvesInCallExpressions() throws {
        let source = """
        fun reduceValues(): Int {
            val values = sequenceOf(1, 2, 3, 4)
            return values.reduceIndexed { index, acc, value -> acc + index * value }
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
                "Expected Sequence.reduceIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "reduceIndexed"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_reduceIndexed"))
        }
    }

    func testSequenceFlatMapResolvesInCallExpressions() throws {
        let source = """
        fun expand(): Sequence<Int> {
            val values = sequenceOf(1, 2)
            return values.flatMap { value -> listOf(value, value * 10) }
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
                "Expected Sequence.flatMap surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "flatMap"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_flatMap"))
        }
    }

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

    func testSequenceRunningFoldIndexedResolvesInCallExpressions() throws {
        let source = """
        fun indexedTotals(): Sequence<Int> {
            return sequenceOf(1, 2, 3).runningFoldIndexed(10) { index, acc, value ->
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
                "Expected Sequence.runningFoldIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "runningFoldIndexed"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_runningFoldIndexed"))
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

    func testSequenceToListResolvesInCallExpressions() throws {
        let source = """
        fun collectValues(): List<Int> {
            val values = sequenceOf(1, 2, 3)
            return values.toList()
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
                "Expected Sequence.toList surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "toList"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_to_list"))
        }
    }

    func testSequenceToHashSetResolvesInCallExpressions() throws {
        let source = """
        fun collectUnique(): MutableSet<Int> {
            val values = sequenceOf(3, 1, 2, 1, 3)
            return values.toHashSet()
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
                "Expected Sequence.toHashSet surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "toHashSet"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_toHashSet"))
        }
    }

    func testSequenceRandomOrNullResolvesInCallExpressions() throws {
        let source = """
        fun pickValue(): Int? {
            val values = sequenceOf(7)
            return values.randomOrNull()
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
                "Expected Sequence.randomOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "randomOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_randomOrNull"))
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

    func testSequenceSortedByResolvesInCallExpressions() throws {
        let source = """
        fun sortedValues(): Sequence<String> {
            val values = sequenceOf("cc", "a", "bbb")
            return values.sortedBy { value -> value.length }
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
                "Expected Sequence.sortedBy surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "sortedBy"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_sortedBy"))
        }
    }

    func testSequenceTakeLastWhileResolvesInCallExpressions() throws {
        let source = """
        fun trailingLarge(): List<Int> {
            val values = sequenceOf(1, 3, 4, 2, 5, 6)
            return values.takeLastWhile { value -> value > 2 }
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
                "Expected Sequence.takeLastWhile surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "takeLastWhile"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_takeLastWhile"))
        }
    }

    func testSequenceTakeWhileResolvesInCallExpressions() throws {
        let source = """
        fun leadingSmall(): Sequence<Int> {
            val values = sequenceOf(1, 2, 3, 4, 2)
            return values.takeWhile { value -> value < 4 }
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
                "Expected Sequence.takeWhile surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "takeWhile"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_takeWhile"))
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

    func testSequenceSortedResolvesInCallExpressions() throws {
        let source = """
        fun sortedValues(): Sequence<Int> {
            val values = sequenceOf(3, 1, 2)
            return values.sorted()
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
                "Expected Sequence.sorted surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "sorted"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_sorted"))
        }
    }

    func testSequenceToMutableListResolvesInCallExpressions() throws {
        let source = """
        fun collectMutableValues(): MutableList<Int> {
            val values = sequenceOf(1, 2, 3)
            return values.toMutableList()
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
                "Expected Sequence.toMutableList surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "toMutableList"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_toMutableList"))
        }
    }

    func testSequenceToCollectionResolvesInCallExpressions() throws {
        let source = """
        fun collectIntoDestination(): MutableList<Int> {
            val values = sequenceOf(1, 2, 3)
            val destination = mutableListOf(0)
            return values.toCollection(destination)
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
                "Expected Sequence.toCollection surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "toCollection"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_toCollection"))
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

    func testSequencePlusElementResolvesInCallExpressions() throws {
        let source = """
        fun appendValue(): Sequence<Int> {
            val values = sequenceOf(1, 2, 3)
            return values.plusElement(4)
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
                "Expected Sequence.plusElement surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "plusElement"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_plus_element"))
        }
    }

    func testSequenceNoneResolvesInCallExpressions() throws {
        let source = """
        fun hasNoValues(): Boolean {
            val values = emptySequence<Int>()
            return values.none()
        }

        fun hasNoEvenValues(): Boolean {
            val values = sequenceOf(1, 3, 5)
            return values.none { value -> value % 2 == 0 }
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
                "Expected Sequence.none surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "none"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_none"))
        }
    }

    func testSequenceDistinctByResolvesInCallExpressions() throws {
        let source = """
        fun uniqueByParity(): Sequence<Int> {
            val values = sequenceOf(1, 2, 3, 4)
            return values.distinctBy { value -> value % 2 }
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
                "Expected Sequence.distinctBy surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "distinctBy"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_distinctBy"))
        }
    }

    func testSequenceZipWithNextResolvesInCallExpressions() throws {
        let source = """
        fun adjacentPairCount(): Int {
            val values = sequenceOf(1, 2, 4, 8)
            val pairs = values.zipWithNext().take(2).toList()
            val diffs = values.zipWithNext { left, right -> right - left }.take(2).toList()
            return pairs.size + diffs.size
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
                "Expected Sequence.zipWithNext surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "zipWithNext"]
                .map { ctx.interner.intern($0) }
            let transformFQName = memberFQName + [ctx.interner.intern("transform")]
            let links = Set(
                (sema.symbols.lookupAll(fqName: memberFQName) + sema.symbols.lookupAll(fqName: transformFQName))
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_zipWithNext"))
            XCTAssertTrue(links.contains("kk_sequence_zipWithNextTransform"))

            let noArgSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            let noArgSignature = try XCTUnwrap(sema.symbols.functionSignature(for: noArgSymbol))
            guard case let .classType(noArgReturnType) = sema.types.kind(of: noArgSignature.returnType) else {
                return XCTFail("Expected Sequence.zipWithNext() to return Sequence<Pair<T, T>>")
            }
            XCTAssertEqual(
                try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(noArgReturnType.classSymbol)?.name)),
                "Sequence"
            )

            let transformSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: transformFQName))
            let transformSignature = try XCTUnwrap(sema.symbols.functionSignature(for: transformSymbol))
            guard case let .classType(transformReturnType) = sema.types.kind(of: transformSignature.returnType) else {
                return XCTFail("Expected Sequence.zipWithNext(transform) to return Sequence<R>")
            }
            XCTAssertEqual(
                try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(transformReturnType.classSymbol)?.name)),
                "Sequence"
            )
        }
    }

    func testSequenceOnEachResolvesInCallExpressions() throws {
        let source = """
        fun traceValues(): Sequence<Int> {
            var sum = 0
            val values = sequenceOf(1, 2, 3)
            return values.onEach { value -> sum += value }
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
                "Expected Sequence.onEach surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "onEach"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_onEach"))
        }
    }

    func testSequenceOnEachIndexedResolvesInCallExpressions() throws {
        let source = """
        fun traceIndexedValues(): Sequence<Int> {
            var trace = ""
            val values = sequenceOf(10, 20, 30)
            return values.onEachIndexed { index, value -> trace += "$index:$value;" }
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
                "Expected Sequence.onEachIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "onEachIndexed"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_onEachIndexed"))
        }
    }

    func testSequenceUnionResolvesInCallExpressions() throws {
        let source = """
        fun unionValues(): Set<Int> {
            val values = sequenceOf(1, 2, 3)
            return values.union(listOf(3, 4))
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
                "Expected Sequence.union surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "union"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_union"))
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

    func testSequenceToSetResolvesInCallExpressions() throws {
        let source = """
        fun collectValues(): Set<Int> {
            val values = sequenceOf(1, 2, 3, 2)
            return values.toSet()
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
                "Expected Sequence.toSet surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "toSet"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_toSet"))
        }
    }

    func testSequenceToMutableSetResolvesInCallExpressions() throws {
        let source = """
        fun collectMutableValues(): MutableSet<Int> {
            val values = sequenceOf(1, 2, 3, 2)
            return values.toMutableSet()
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
                "Expected Sequence.toMutableSet surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "toMutableSet"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_toMutableSet"))
        }
    }

    func testSequenceWindowedResolvesInCallExpressions() throws {
        let source = """
        fun windows(): Sequence<List<Int>> {
            val values = sequenceOf(1, 2, 3, 4, 5)
            val sizes = values.windowed(3, 2, true) { window -> window.size }
            return values.windowed(3, 2, true)
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
                "Expected Sequence.windowed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "windowed"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_windowed"))
            XCTAssertTrue(links.contains("kk_sequence_windowed_transform"))
        }
    }

    func testSequenceConstrainOnceResolvesInCallExpressions() throws {
        let source = """
        fun singleUse(): Sequence<Int> {
            val values = sequenceOf(1, 2, 3)
            return values.constrainOnce()
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
                "Expected Sequence.constrainOnce surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "constrainOnce"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_sequence_constrainOnce"))
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

    func testSequenceMinWithOrNullResolvesInCallExpressions() throws {
        let source = """
        fun smallestByReverseOrder(): Int? {
            val values = sequenceOf(5, 2, 3)
            return values.minWithOrNull(reverseOrder<Int>())
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
                "Expected Sequence.minWithOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "minWithOrNull"]
                .map { ctx.interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: memberFQName)
            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertTrue(links.contains("kk_sequence_minWithOrNull"))

            let symbol = try XCTUnwrap(symbols.first)
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.parameterTypes.count, 1)
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
}
