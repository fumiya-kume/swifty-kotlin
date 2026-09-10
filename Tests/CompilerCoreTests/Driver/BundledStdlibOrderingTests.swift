#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BundledStdlibOrderingTests {
    @Test
    func testBundledSourcesAreLoadedBeforeUserInputsInDictionaryOrder() throws {
        try withTemporaryFiles(contents: [
            "fun alpha(): Int = 1",
            "fun beta(): Int = 2",
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths)

            try LoadSourcesPhase().run(ctx)

            let orderedPaths = ctx.sourceManager.fileIDs().map { ctx.sourceManager.path(of: $0) }
            let bundledEntries = orderedPaths.enumerated()
                .filter { $0.element.hasPrefix("__bundled_") }
            let userEntries = orderedPaths.enumerated()
                .filter { paths.contains($0.element) }

            #expect(!bundledEntries.isEmpty, "Bundled stdlib sources should be injected.")
            #expect(userEntries.count == paths.count)

            let lastBundledOffset = try #require(bundledEntries.map { $0.offset }.max())
            let firstUserOffset = try #require(userEntries.map { $0.offset }.min())
            #expect(lastBundledOffset < firstUserOffset)

            let bundledPaths = bundledEntries.map { $0.element }
            #expect(bundledPaths == bundledPaths.sorted())
            #expect(bundledPaths.contains { $0.hasSuffix("kotlin/text/StringIndentFormat.kt") })
            #expect(bundledPaths.contains { $0.hasSuffix("kotlin/text/StringSearchReplace.kt") })
        }
    }

    @Test
    func testLexAndParseRecordBundledStdlibSubPhases() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path], frontendFlags: ["time-phases"])
            let timer = PhaseTimer()
            ctx.installPhaseTimer(timer)

            try LoadSourcesPhase().run(ctx)

            timer.beginPhase(LexPhase.name)
            try LexPhase().run(ctx)
            timer.endPhase()

            timer.beginPhase(ParsePhase.name)
            try ParsePhase().run(ctx)
            timer.endPhase()

            let lexRecord = try #require(timer.phaseRecords.first { $0.name == LexPhase.name })
            let parseRecord = try #require(timer.phaseRecords.first { $0.name == ParsePhase.name })
            #expect(lexRecord.subRecords.contains { $0.name == "bundled-stdlib" })
            #expect(parseRecord.subRecords.contains { $0.name == "bundled-stdlib" })
        }
    }

    @Test
    func testRandomInteropUsesKotlinStdlibPlatformFilename() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])

            try LoadSourcesPhase().run(ctx)

            let bundledPaths = ctx.sourceManager.fileIDs()
                .map { ctx.sourceManager.path(of: $0) }
                .filter { $0.hasPrefix("__bundled_") }

            #expect(bundledPaths.contains("__bundled_kotlin/random/PlatformRandom.kt"))
            #expect(!bundledPaths.contains("__bundled_kotlin/random/JavaRandomInterop.kt"))
        }
    }
}
#endif
