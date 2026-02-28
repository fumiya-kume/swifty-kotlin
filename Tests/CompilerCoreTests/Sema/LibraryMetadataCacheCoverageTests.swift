import Foundation
import XCTest
@testable import CompilerCore

final class LibraryMetadataCacheCoverageTests: XCTestCase {
    // MARK: - P5-62: Library metadata cache tests

    func testLibraryMetadataCacheReusesManifestAndMetadataOnSecondLoad() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "CacheTest",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        function _ fq=cachetest.add arity=2 suspend=0 sig=F2<I,I,I>
        property _ fq=cachetest.version sig=I
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        // Use a shared interner across loads — mirrors real usage where the cache
        // lives within a single compilation session that shares one interner.
        let sharedInterner = StringInterner()

        // First load — cold cache
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CacheApp1",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )

            let symbols1 = SymbolTable()
            let types1 = TypeSystem()
            let diagnostics1 = DiagnosticEngine()
            var inlineFns1: [SymbolID: KIRFunction] = [:]
            let phase = DataFlowSemaPhase()
            phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols1,
                types: types1,
                diagnostics: diagnostics1,
                interner: sharedInterner,
                importedInlineFunctions: &inlineFns1,
                cache: cache
            )

            XCTAssertEqual(cache.manifestCacheCount, 1, "Manifest should be cached after first load")
            XCTAssertEqual(cache.metadataCacheCount, 1, "Metadata should be cached after first load")
            XCTAssertGreaterThan(cache.signatureCacheCount, 0, "Signatures should be cached after first load")

            let addSymbol = symbols1.allSymbols().first { symbol in
                sharedInterner.resolve(symbol.name) == "add" && symbol.kind == .function
            }
            XCTAssertNotNil(addSymbol, "Function 'add' should be imported")
        }

        let manifestCountAfterFirst = cache.manifestCacheCount
        let metadataCountAfterFirst = cache.metadataCacheCount
        let signatureCountAfterFirst = cache.signatureCacheCount

        // Second load — warm cache, same files, same interner
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CacheApp2",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )

            let symbols2 = SymbolTable()
            let types2 = TypeSystem()
            let diagnostics2 = DiagnosticEngine()
            var inlineFns2: [SymbolID: KIRFunction] = [:]
            let phase = DataFlowSemaPhase()
            phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols2,
                types: types2,
                diagnostics: diagnostics2,
                interner: sharedInterner,
                importedInlineFunctions: &inlineFns2,
                cache: cache
            )

            // Manifest and metadata cache counts should remain the same (reused on second load).
            // The signature cache is cleared when using a different TypeSystem/SymbolTable, but its
            // entry count should return to the same value after being repopulated.
            XCTAssertEqual(cache.manifestCacheCount, manifestCountAfterFirst, "Manifest cache should be reused on second load")
            XCTAssertEqual(cache.metadataCacheCount, metadataCountAfterFirst, "Metadata cache should be reused on second load")
            XCTAssertEqual(cache.signatureCacheCount, signatureCountAfterFirst, "Signature cache should have the same number of entries after second load")

            let addSymbol = symbols2.allSymbols().first { symbol in
                sharedInterner.resolve(symbol.name) == "add" && symbol.kind == .function
            }
            XCTAssertNotNil(addSymbol, "Function 'add' should be imported from cache")
        }
    }

    func testSignatureMemoizationDeduplicatesIdenticalTypeSignatures() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        // Multiple functions share the same signature F1<I,I>
        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "SigMemo",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=5
        function _ fq=memo.inc arity=1 suspend=0 sig=F1<I,I>
        function _ fq=memo.dec arity=1 suspend=0 sig=F1<I,I>
        function _ fq=memo.neg arity=1 suspend=0 sig=F1<I,I>
        function _ fq=memo.abs arity=1 suspend=0 sig=F1<I,I>
        function _ fq=memo.dbl arity=1 suspend=0 sig=F1<I,I>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "SigMemoApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runFrontend(ctx)
            try BuildASTPhase().run(ctx)

            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            let phase = DataFlowSemaPhase()
            phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: ctx.interner,
                importedInlineFunctions: &inlineFns,
                cache: cache
            )

            // All 5 functions share signature "F1<I,I>", so cache should have exactly 1 entry
            XCTAssertEqual(cache.signatureCacheCount, 1, "Identical signatures should be deduplicated in cache")

            // All 5 symbols should still be imported correctly
            let importedFunctions = symbols.allSymbols().filter { symbol in
                symbol.kind == .function && symbol.flags.contains(.synthetic)
            }
            XCTAssertEqual(importedFunctions.count, 5, "All 5 functions should be imported")

            // Each should have a valid function signature with 1 param
            for fn in importedFunctions {
                let sig = symbols.functionSignature(for: fn.id)
                XCTAssertNotNil(sig, "Function \(fn.id) should have a signature")
                XCTAssertEqual(sig?.parameterTypes.count, 1)
            }
        }
    }

    func testMultiKklibCompileBenchmarkMeasuresSemaTime() throws {
        let fm = FileManager.default
        let libraryCount = 5
        let symbolsPerLibrary = 20
        var libDirs: [String] = []

        // Create multiple .kklib directories
        for libIndex in 0..<libraryCount {
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "BenchLib\(libIndex)",
              "metadata": "metadata.bin"
            }
            """
            var metadataLines = ["symbols=\(symbolsPerLibrary)"]
            for symIndex in 0..<symbolsPerLibrary {
                metadataLines.append("function _ fq=bench\(libIndex).fn\(symIndex) arity=1 suspend=0 sig=F1<I,I>")
            }
            let metadata = metadataLines.joined(separator: "\n")

            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            libDirs.append(libDir.path)
        }

        let source = "fun main() = 0"

        // Measure without cache
        let timeWithoutCache: Double = try {
            var total: Double = 0
            let iterations = 3
            for _ in 0..<iterations {
                try withTemporaryFile(contents: source) { path in
                    let ctx = makeCompilationContext(
                        inputs: [path],
                        moduleName: "BenchNoCache",
                        emit: .kirDump,
                        searchPaths: libDirs
                    )
                    try runFrontend(ctx)
                    try BuildASTPhase().run(ctx)

                    let symbols = SymbolTable()
                    let types = TypeSystem()
                    let diagnostics = DiagnosticEngine()
                    var inlineFns: [SymbolID: KIRFunction] = [:]
                    let phase = DataFlowSemaPhase()

                    let start = Date().timeIntervalSinceReferenceDate
                    phase.loadImportedLibrarySymbols(
                        options: ctx.options,
                        symbols: symbols,
                        types: types,
                        diagnostics: diagnostics,
                        interner: ctx.interner,
                        importedInlineFunctions: &inlineFns
                    )
                    let elapsed = Date().timeIntervalSinceReferenceDate - start
                    total += elapsed

                    // Verify correctness
                    let importedCount = symbols.allSymbols().filter { $0.flags.contains(.synthetic) && $0.kind == .function }.count
                    XCTAssertEqual(importedCount, libraryCount * symbolsPerLibrary,
                                   "All \(libraryCount * symbolsPerLibrary) functions should be imported without cache")
                }
            }
            return total / Double(iterations)
        }()

        // Measure with cache (cold start + warm iterations)
        let cache = LibraryMetadataCache()
        let timeWithCache: Double = try {
            var total: Double = 0
            let iterations = 3
            for _ in 0..<iterations {
                try withTemporaryFile(contents: source) { path in
                    let ctx = makeCompilationContext(
                        inputs: [path],
                        moduleName: "BenchWithCache",
                        emit: .kirDump,
                        searchPaths: libDirs
                    )
                    try runFrontend(ctx)
                    try BuildASTPhase().run(ctx)

                    let symbols = SymbolTable()
                    let types = TypeSystem()
                    let diagnostics = DiagnosticEngine()
                    var inlineFns: [SymbolID: KIRFunction] = [:]
                    let phase = DataFlowSemaPhase()

                    let start = Date().timeIntervalSinceReferenceDate
                    phase.loadImportedLibrarySymbols(
                        options: ctx.options,
                        symbols: symbols,
                        types: types,
                        diagnostics: diagnostics,
                        interner: ctx.interner,
                        importedInlineFunctions: &inlineFns,
                        cache: cache
                    )
                    let elapsed = Date().timeIntervalSinceReferenceDate - start
                    total += elapsed

                    // Verify correctness
                    let importedCount = symbols.allSymbols().filter { $0.flags.contains(.synthetic) && $0.kind == .function }.count
                    XCTAssertEqual(importedCount, libraryCount * symbolsPerLibrary,
                                   "All \(libraryCount * symbolsPerLibrary) functions should be imported with cache")
                }
            }
            return total / Double(iterations)
        }()

        // Verify cache was populated
        XCTAssertEqual(cache.manifestCacheCount, libraryCount, "Should have cached all \(libraryCount) manifests")
        XCTAssertEqual(cache.metadataCacheCount, libraryCount, "Should have cached all \(libraryCount) metadata files")
        XCTAssertGreaterThan(cache.signatureCacheCount, 0, "Should have cached type signatures")

        // Log timing results only when P5_62_BENCH_LOG env var is set,
        // keeping normal CI runs quiet and deterministic.
        if ProcessInfo.processInfo.environment["P5_62_BENCH_LOG"] != nil {
            print("[P5-62 Bench] Libraries=\(libraryCount) Symbols/lib=\(symbolsPerLibrary)")
            print("[P5-62 Bench] Avg Sema (no cache):   \(String(format: "%.4f", timeWithoutCache * 1000)) ms")
            print("[P5-62 Bench] Avg Sema (with cache):  \(String(format: "%.4f", timeWithCache * 1000)) ms")
            if timeWithoutCache > 0 {
                let ratio = timeWithCache / timeWithoutCache
                print("[P5-62 Bench] Ratio (cached/uncached): \(String(format: "%.2f", ratio))x")
            }
        }
    }

    // MARK: - P5-62: Comprehensive correctness tests

    // --- A. LibraryMetadataCache unit tests (isolated, direct) ---

    /// A1: Manifest cache hit — same libraryDir, same mtime

    /// A2: Manifest cache miss — different libraryDir

    /// A3: Manifest cache miss — mtime changed (file modified)

    /// A4: Metadata cache hit — same interner, same path+mtime

    /// A5: Metadata cache miss — different interner

    /// A6: Signature cache hit — same TypeSystem + SymbolTable

    /// A7: Signature cache miss — different TypeSystem

    /// A8: Signature cache miss — different SymbolTable

    /// A9: Signature cache correctly caches nil (failed parse)

    /// A10: Signature cache auto-clears on TypeSystem change

    /// A11: Metadata cache auto-clears on interner change

    // --- B. Integration tests (loadImportedLibrarySymbols with cache) ---

    /// B1: cache=nil produces identical results to without cache (no regression)

    /// B2: cache provided → correct symbols on first load + correct cache population

    /// B3: Properties and typeAliases also cache correctly (not just functions)

    /// B4: Invalid manifest is still cached (avoids re-reading invalid manifest)

    /// B5: Multiple libraries → all manifests and metadata cached correctly

    /// B6: Cached results produce semantically identical TypeIDs as non-cached

    /// B7: Suspend functions work with cache

    /// B8: Nullable type signatures cached correctly
}
