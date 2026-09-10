#if canImport(Testing)
import CompilerCore
import Foundation
import GoldenHarnessSupport
import Testing
import TestStdlibCache

struct GoldenHarnessCaseBatch: Sendable, CustomTestStringConvertible {
    let cases: [GoldenHarnessCase]

    var testDescription: String {
        guard let first = cases.first else {
            return "empty"
        }
        guard let last = cases.last, last.basename != first.basename else {
            return first.basename
        }
        return "\(first.basename)...\(last.basename) (\(cases.count) cases)"
    }
}

private struct GoldenHarnessShard: Equatable {
    private static let indexKey = "KSWIFTK_GOLDEN_SHARD_INDEX"
    private static let countKey = "KSWIFTK_GOLDEN_SHARD_COUNT"

    let index: Int
    let count: Int

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GoldenHarnessShard? {
        let rawIndex = environment[indexKey]
        let rawCount = environment[countKey]

        guard rawIndex != nil || rawCount != nil else {
            return nil
        }
        guard
            let rawIndex,
            let rawCount,
            let index = Int(rawIndex),
            let count = Int(rawCount),
            count > 0,
            index >= 0,
            index < count
        else {
            fatalError(
                "\(indexKey) and \(countKey) must be integers satisfying 0 <= index < count"
            )
        }
        return GoldenHarnessShard(index: index, count: count)
    }

    func select<T>(_ values: [T]) -> [T] {
        values.enumerated().compactMap { offset, value in
            offset % count == index ? value : nil
        }
    }
}

private enum GoldenHarnessStaticCases {
    private static let batchSize = 8

    static let lexer = batches(suiteName: "Lexer")
    static let parser = batches(suiteName: "Parser")
    static let sema = batches(suiteName: "Sema")
    static let diagnostics = batches(suiteName: "Diagnostics")

    private static func batches(suiteName: String) -> [GoldenHarnessCaseBatch] {
        let cases = GoldenHarness.loadCasesOrCrash(suiteName: suiteName)
        let allBatches = stride(from: 0, to: cases.count, by: batchSize).map { startIndex in
            let endIndex = min(startIndex + batchSize, cases.count)
            return GoldenHarnessCaseBatch(cases: Array(cases[startIndex ..< endIndex]))
        }

        guard let shard = GoldenHarnessShard.fromEnvironment() else {
            return allBatches
        }
        let selectedBatches = shard.select(allBatches)
        print(
            "GoldenHarness: \(suiteName) shard \(shard.index)/\(shard.count) "
                + "selected \(selectedBatches.count) of \(allBatches.count) batches"
        )
        return selectedBatches
    }
}

@Suite
struct GoldenHarnessShardingTests {
    @Test
    func disabledWithoutEnvironment() {
        #expect(GoldenHarnessShard.fromEnvironment([:]) == nil)
    }

    @Test
    func selectsInterleavedValues() throws {
        let shard = try #require(
            GoldenHarnessShard.fromEnvironment([
                "KSWIFTK_GOLDEN_SHARD_INDEX": "1",
                "KSWIFTK_GOLDEN_SHARD_COUNT": "6",
            ])
        )
        #expect(shard.select(Array(0 ..< 8)) == [1, 7])
    }
}

@Suite("Golden.Lexer")
struct GoldenLexerGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.lexer)
    func matchesGolden(batch: GoldenHarnessCaseBatch) throws {
        try runGoldenTests(suiteName: "Lexer", batch: batch)
    }
}

@Suite("Golden.Parser")
struct GoldenParserGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.parser)
    func matchesGolden(batch: GoldenHarnessCaseBatch) throws {
        try runGoldenTests(suiteName: "Parser", batch: batch)
    }
}

@Suite("Golden.Sema")
struct GoldenSemaGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.sema)
    func matchesGolden(batch: GoldenHarnessCaseBatch) throws {
        try runGoldenTests(suiteName: "Sema", batch: batch)
    }
}

@Suite("Golden.Diagnostics")
struct GoldenDiagnosticsGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.diagnostics)
    func matchesGolden(batch: GoldenHarnessCaseBatch) throws {
        try runGoldenTests(suiteName: "Diagnostics", batch: batch)
    }
}

/// Path of the shared prebuilt stdlib `.kklib`, prepared once per test
/// process. Feeding it to each golden worker makes every case resolve stdlib
/// symbols from serialized metadata instead of re-running the bundled-stdlib
/// source pipeline (the dominant per-case cost). `nil` keeps the historical
/// source-injection behavior, e.g. when the artifact cannot be built locally.
private func goldenStdlibLibraryPath() -> String? {
    TestStdlibCache.shared.prepare()
    return CompilerOptions.defaultStdlibLibraryPath
}

private func runGoldenTests(suiteName: String, batch: GoldenHarnessCaseBatch) throws {
    let results = try GoldenHarness.renderBatchInSubprocess(
        suiteName: suiteName,
        sourcePaths: batch.cases.map(\.sourcePath),
        stdlibLibraryPath: goldenStdlibLibraryPath()
    )

    for (caseFile, result) in zip(batch.cases, results) {
        if let errorDescription = result.errorDescription {
            Issue.record("Golden worker failed for \(caseFile.basename): \(errorDescription)")
            continue
        }
        guard let renderedActual = result.output else {
            Issue.record("Golden worker returned no output for \(caseFile.basename)")
            continue
        }

        do {
            try verifyGolden(suiteName: suiteName, caseFile: caseFile, renderedActual: renderedActual)
        } catch {
            Issue.record("Golden verification failed for \(caseFile.basename): \(error)")
        }
    }
}

private func verifyGolden(
    suiteName: String,
    caseFile: GoldenHarnessCase,
    renderedActual: String
) throws {
    if try GoldenHarness.persistIfUpdating(suiteName: suiteName, sourcePath: caseFile.sourcePath, actual: renderedActual) {
        return
    }
    let actual   = GoldenHarness.normalizedForComparison(suiteName: suiteName, output: renderedActual)
    let expected = GoldenHarness.normalizedForComparison(suiteName: suiteName, output: try GoldenHarness.loadExpectedGolden(sourcePath: caseFile.sourcePath))
    #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(caseFile.basename)"))
}
#endif
