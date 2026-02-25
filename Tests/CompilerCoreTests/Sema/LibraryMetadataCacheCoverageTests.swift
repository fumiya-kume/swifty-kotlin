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
            let phase = DataFlowSemaPassPhase()
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
            let phase = DataFlowSemaPassPhase()
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
            let phase = DataFlowSemaPassPhase()
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
                    let phase = DataFlowSemaPassPhase()

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
                    let phase = DataFlowSemaPassPhase()

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
    func testManifestCacheHitOnSameKey() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let manifestJSON = """
        { "formatVersion": 1, "moduleName": "A1", "metadata": "metadata.bin" }
        """
        try manifestJSON.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "symbols=0".write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let info = DataFlowSemaPassPhase.LibraryManifestInfo(metadataPath: libDir.appendingPathComponent("metadata.bin").path, inlineKIRDir: nil, isValid: true)
        let target = TargetTriple.hostDefault()
        cache.cacheManifestInfo(info, libraryDir: libDir.path, target: target)

        let retrieved = cache.cachedManifestInfo(libraryDir: libDir.path, target: target)
        XCTAssertNotNil(retrieved, "Should hit cache for same libraryDir + mtime + target")
        XCTAssertEqual(retrieved?.metadataPath, info.metadataPath)
        XCTAssertEqual(retrieved?.isValid, true)
    }

    /// A2: Manifest cache miss — different libraryDir
    func testManifestCacheMissOnDifferentLibraryDir() throws {
        let fm = FileManager.default
        let baseDir1 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir1 = baseDir1.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir1, withIntermediateDirectories: true)
        try "{}".write(to: libDir1.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let baseDir2 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir2 = baseDir2.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir2, withIntermediateDirectories: true)
        try "{}".write(to: libDir2.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let info = DataFlowSemaPassPhase.LibraryManifestInfo(metadataPath: "/some/path", inlineKIRDir: nil, isValid: true)
        let target = TargetTriple.hostDefault()
        cache.cacheManifestInfo(info, libraryDir: libDir1.path, target: target)

        let retrieved = cache.cachedManifestInfo(libraryDir: libDir2.path, target: target)
        XCTAssertNil(retrieved, "Should miss cache for different libraryDir")
    }

    /// A3: Manifest cache miss — mtime changed (file modified)
    func testManifestCacheMissOnMtimeChange() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let manifestPath = libDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifestPath, atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let info = DataFlowSemaPassPhase.LibraryManifestInfo(metadataPath: "/some/path", inlineKIRDir: nil, isValid: true)
        let target = TargetTriple.hostDefault()
        cache.cacheManifestInfo(info, libraryDir: libDir.path, target: target)

        // Verify hit before modification
        XCTAssertNotNil(cache.cachedManifestInfo(libraryDir: libDir.path, target: target), "Should hit before modification")

        // Explicitly set a different mtime to deterministically invalidate the cache
        // (avoids relying on filesystem mtime granularity which can be 1s on some systems)
        let futureDate = Date(timeIntervalSinceNow: 10)
        try fm.setAttributes([.modificationDate: futureDate], ofItemAtPath: manifestPath.path)

        let retrieved = cache.cachedManifestInfo(libraryDir: libDir.path, target: target)
        XCTAssertNil(retrieved, "Should miss cache after file modification changes mtime")
    }

    /// A4: Metadata cache hit — same interner, same path+mtime
    func testMetadataCacheHitWithSameInterner() throws {
        let fm = FileManager.default
        let metadataPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin").path
        try "symbols=0".write(toFile: metadataPath, atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let interner = StringInterner()
        let record = DataFlowSemaPassPhase.ImportedLibrarySymbolRecord(
            kind: .function, mangledName: "", fqName: [interner.intern("test")],
            arity: 0, isSuspend: false, isInline: false, typeSignature: nil,
            externalLinkName: nil, declaredFieldCount: nil, declaredInstanceSizeWords: nil,
            declaredVtableSize: nil, declaredItableSize: nil, superFQName: nil,
            fieldOffsets: [], vtableSlots: [], itableSlots: [], isDataClass: false,
            isSealedClass: false, isValueClass: false, valueClassUnderlyingTypeSig: nil, annotations: [], sealedSubclassFQNames: []
        )
        cache.cacheMetadataRecords([record], metadataPath: metadataPath, interner: interner)

        let retrieved = cache.cachedMetadataRecords(metadataPath: metadataPath, interner: interner)
        XCTAssertNotNil(retrieved, "Should hit cache with same interner")
        XCTAssertEqual(retrieved?.count, 1)
    }

    /// A5: Metadata cache miss — different interner
    func testMetadataCacheMissWithDifferentInterner() throws {
        let fm = FileManager.default
        let metadataPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin").path
        try "symbols=0".write(toFile: metadataPath, atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let interner1 = StringInterner()
        let record = DataFlowSemaPassPhase.ImportedLibrarySymbolRecord(
            kind: .function, mangledName: "", fqName: [interner1.intern("test")],
            arity: 0, isSuspend: false, isInline: false, typeSignature: nil,
            externalLinkName: nil, declaredFieldCount: nil, declaredInstanceSizeWords: nil,
            declaredVtableSize: nil, declaredItableSize: nil, superFQName: nil,
            fieldOffsets: [], vtableSlots: [], itableSlots: [], isDataClass: false,
            isSealedClass: false, isValueClass: false, valueClassUnderlyingTypeSig: nil, annotations: [], sealedSubclassFQNames: []
        )
        cache.cacheMetadataRecords([record], metadataPath: metadataPath, interner: interner1)

        let interner2 = StringInterner()
        let retrieved = cache.cachedMetadataRecords(metadataPath: metadataPath, interner: interner2)
        XCTAssertNil(retrieved, "Should miss cache with different interner instance")
    }

    /// A6: Signature cache hit — same TypeSystem + SymbolTable
    func testSignatureCacheHitWithSameTypeSystemAndSymbolTable() {
        let cache = LibraryMetadataCache()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType, for: "I", types: types, symbols: symbols)

        let retrieved = cache.cachedSignature("I", types: types, symbols: symbols)
        XCTAssertNotNil(retrieved, "Outer optional should be non-nil (cache hit)")
        XCTAssertEqual(retrieved!, intType, "Should return the cached TypeID")
    }

    /// A7: Signature cache miss — different TypeSystem
    func testSignatureCacheMissWithDifferentTypeSystem() {
        let cache = LibraryMetadataCache()
        let types1 = TypeSystem()
        let symbols = SymbolTable()

        let intType = types1.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType, for: "I", types: types1, symbols: symbols)

        let types2 = TypeSystem()
        let retrieved = cache.cachedSignature("I", types: types2, symbols: symbols)
        XCTAssertNil(retrieved, "Should miss cache with different TypeSystem")
    }

    /// A8: Signature cache miss — different SymbolTable
    func testSignatureCacheMissWithDifferentSymbolTable() {
        let cache = LibraryMetadataCache()
        let types = TypeSystem()
        let symbols1 = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType, for: "I", types: types, symbols: symbols1)

        let symbols2 = SymbolTable()
        let retrieved = cache.cachedSignature("I", types: types, symbols: symbols2)
        XCTAssertNil(retrieved, "Should miss cache with different SymbolTable")
    }

    /// A9: Signature cache correctly caches nil (failed parse)
    func testSignatureCacheCachesNilForFailedParse() {
        let cache = LibraryMetadataCache()
        let types = TypeSystem()
        let symbols = SymbolTable()

        cache.cacheSignature(nil, for: "INVALID", types: types, symbols: symbols)

        let retrieved = cache.cachedSignature("INVALID", types: types, symbols: symbols)
        // Outer optional should be non-nil (cache hit), inner should be nil (cached failure)
        XCTAssertNotNil(retrieved, "Outer optional should be non-nil (cache hit for nil value)")
        XCTAssertNil(retrieved!, "Inner value should be nil (cached failed parse)")
        XCTAssertEqual(cache.signatureCacheCount, 1)
    }

    /// A10: Signature cache auto-clears on TypeSystem change
    func testSignatureCacheAutoClearsOnTypeSystemChange() {
        let cache = LibraryMetadataCache()
        let types1 = TypeSystem()
        let symbols = SymbolTable()

        let intType1 = types1.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType1, for: "I", types: types1, symbols: symbols)
        cache.cacheSignature(intType1, for: "J", types: types1, symbols: symbols)
        XCTAssertEqual(cache.signatureCacheCount, 2)

        // Switch to new TypeSystem — old entries should be cleared
        let types2 = TypeSystem()
        let intType2 = types2.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType2, for: "I", types: types2, symbols: symbols)
        XCTAssertEqual(cache.signatureCacheCount, 1, "Old entries should have been cleared")
    }

    /// A11: Metadata cache auto-clears on interner change
    func testMetadataCacheAutoClearsOnInternerChange() throws {
        let fm = FileManager.default
        let metadataPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin").path
        try "symbols=0".write(toFile: metadataPath, atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let interner1 = StringInterner()
        let record = DataFlowSemaPassPhase.ImportedLibrarySymbolRecord(
            kind: .function, mangledName: "", fqName: [interner1.intern("test")],
            arity: 0, isSuspend: false, isInline: false, typeSignature: nil,
            externalLinkName: nil, declaredFieldCount: nil, declaredInstanceSizeWords: nil,
            declaredVtableSize: nil, declaredItableSize: nil, superFQName: nil,
            fieldOffsets: [], vtableSlots: [], itableSlots: [], isDataClass: false,
            isSealedClass: false, isValueClass: false, valueClassUnderlyingTypeSig: nil, annotations: [], sealedSubclassFQNames: []
        )
        cache.cacheMetadataRecords([record], metadataPath: metadataPath, interner: interner1)
        XCTAssertEqual(cache.metadataCacheCount, 1)

        // Switch to new interner — old entries should be cleared on next store
        let interner2 = StringInterner()
        let record2 = DataFlowSemaPassPhase.ImportedLibrarySymbolRecord(
            kind: .property, mangledName: "", fqName: [interner2.intern("test2")],
            arity: 0, isSuspend: false, isInline: false, typeSignature: nil,
            externalLinkName: nil, declaredFieldCount: nil, declaredInstanceSizeWords: nil,
            declaredVtableSize: nil, declaredItableSize: nil, superFQName: nil,
            fieldOffsets: [], vtableSlots: [], itableSlots: [], isDataClass: false,
            isSealedClass: false, isValueClass: false, valueClassUnderlyingTypeSig: nil, annotations: [], sealedSubclassFQNames: []
        )
        let otherPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin").path
        try "symbols=0".write(toFile: otherPath, atomically: true, encoding: .utf8)
        cache.cacheMetadataRecords([record2], metadataPath: otherPath, interner: interner2)
        XCTAssertEqual(cache.metadataCacheCount, 1, "Old interner entries should have been cleared")
    }

    // --- B. Integration tests (loadImportedLibrarySymbols with cache) ---

    /// B1: cache=nil produces identical results to without cache (no regression)
    func testLoadImportedSymbolsWithNilCacheMatchesWithoutCache() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NilCacheTest",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=3
        function _ fq=nilcache.add arity=2 suspend=0 sig=F2<I,I,I>
        property _ fq=nilcache.version sig=I
        function _ fq=nilcache.noop arity=0 suspend=0 sig=F0<U>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        // Load without cache
        var symbolNames1: [String] = []
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NoCacheApp", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns
                // cache: nil (default)
            )
            symbolNames1 = symbols.allSymbols()
                .filter { $0.flags.contains(.synthetic) }
                .map { interner.resolve($0.name) }
                .sorted()
        }

        // Load with explicit nil cache
        var symbolNames2: [String] = []
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NilCacheApp", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns,
                cache: nil
            )
            symbolNames2 = symbols.allSymbols()
                .filter { $0.flags.contains(.synthetic) }
                .map { interner.resolve($0.name) }
                .sorted()
        }

        XCTAssertEqual(symbolNames1, symbolNames2, "cache=nil should produce identical symbols as no cache parameter")
        XCTAssertTrue(symbolNames1.contains("add"), "Should contain function 'add'")
        XCTAssertTrue(symbolNames1.contains("version"), "Should contain property 'version'")
        XCTAssertTrue(symbolNames1.contains("noop"), "Should contain function 'noop'")
    }

    /// B2: cache provided → correct symbols on first load + correct cache population
    func testCachePopulatedCorrectlyOnFirstLoad() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "PopulateTest",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        function _ fq=pop.calc arity=1 suspend=0 sig=F1<I,I>
        property _ fq=pop.val sig=I
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        XCTAssertEqual(cache.manifestCacheCount, 0, "Cache should start empty")
        XCTAssertEqual(cache.metadataCacheCount, 0)
        XCTAssertEqual(cache.signatureCacheCount, 0)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "PopApp", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns,
                cache: cache
            )

            // Verify symbols
            let calcSymbol = symbols.allSymbols().first { interner.resolve($0.name) == "calc" && $0.kind == .function }
            XCTAssertNotNil(calcSymbol, "Function 'calc' should be imported")
            let valSymbol = symbols.allSymbols().first { interner.resolve($0.name) == "val" && $0.kind == .property }
            XCTAssertNotNil(valSymbol, "Property 'val' should be imported")

            // Verify function signature is correct
            if let calcID = calcSymbol?.id {
                let sig = symbols.functionSignature(for: calcID)
                XCTAssertNotNil(sig)
                XCTAssertEqual(sig?.parameterTypes.count, 1)
                XCTAssertEqual(types.kind(of: sig!.parameterTypes[0]), .primitive(.int, .nonNull))
                XCTAssertEqual(types.kind(of: sig!.returnType), .primitive(.int, .nonNull))
            }

            // Verify property type is correct
            if let valID = valSymbol?.id {
                let propType = symbols.propertyType(for: valID)
                XCTAssertNotNil(propType)
                XCTAssertEqual(types.kind(of: propType!), .primitive(.int, .nonNull))
            }
        }

        // Verify cache was populated
        XCTAssertEqual(cache.manifestCacheCount, 1, "Should have cached 1 manifest")
        XCTAssertEqual(cache.metadataCacheCount, 1, "Should have cached 1 metadata")
        XCTAssertGreaterThan(cache.signatureCacheCount, 0, "Should have cached signatures")
    }

    /// B3: Properties and typeAliases also cache correctly (not just functions)
    func testCacheWorksForPropertyAndTypeAliasSignatures() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "MixedKinds",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=3
        function _ fq=mixed.fn arity=1 suspend=0 sig=F1<I,I>
        property _ fq=mixed.prop sig=I
        typeAlias _ fq=mixed.MyInt sig=I
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "MixedApp", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns,
                cache: cache
            )

            let fnSym = symbols.allSymbols().first { interner.resolve($0.name) == "fn" && $0.kind == .function }
            let propSym = symbols.allSymbols().first { interner.resolve($0.name) == "prop" && $0.kind == .property }
            let taSym = symbols.allSymbols().first { interner.resolve($0.name) == "MyInt" && $0.kind == .typeAlias }
            XCTAssertNotNil(fnSym, "Function should be imported")
            XCTAssertNotNil(propSym, "Property should be imported")
            XCTAssertNotNil(taSym, "TypeAlias should be imported")

            // The signature "I" is shared by property and typeAlias — verify dedup in cache
            // F1<I,I> is one signature, I is another (shared by prop and typeAlias)
            XCTAssertEqual(cache.signatureCacheCount, 2, "Should have 2 distinct signatures: F1<I,I> and I")
        }
    }

    /// B4: Invalid manifest is still cached (avoids re-reading invalid manifest)
    func testInvalidManifestIsCached() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        // Missing formatVersion → invalid manifest
        let manifest = """
        {
          "moduleName": "BadManifest",
          "metadata": "metadata.bin"
        }
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "symbols=1\nfunction _ fq=bad.fn arity=0 suspend=0".write(
            to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let interner = StringInterner()

        // First load
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "BadApp1", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns,
                cache: cache
            )

            // No symbols should be imported from invalid manifest
            let syntheticFns = symbols.allSymbols().filter { $0.flags.contains(.synthetic) && $0.kind == .function }
            XCTAssertEqual(syntheticFns.count, 0, "Invalid manifest should skip library")
        }

        // The manifest should still be cached (with isValid=false)
        XCTAssertEqual(cache.manifestCacheCount, 1, "Invalid manifest should be cached too")
        // Metadata should NOT be cached (skipped due to invalid manifest)
        XCTAssertEqual(cache.metadataCacheCount, 0, "Metadata should not be cached when manifest is invalid")

        // Second load should reuse cached invalid manifest (no re-read)
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "BadApp2", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns,
                cache: cache
            )

            // Still no symbols
            let syntheticFns = symbols.allSymbols().filter { $0.flags.contains(.synthetic) && $0.kind == .function }
            XCTAssertEqual(syntheticFns.count, 0)
        }

        // Cache count should not have increased
        XCTAssertEqual(cache.manifestCacheCount, 1, "Manifest cache should have been reused")
    }

    /// B5: Multiple libraries → all manifests and metadata cached correctly
    func testMultipleLibrariesAllCached() throws {
        let fm = FileManager.default
        var libDirs: [String] = []

        for i in 0..<3 {
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
            let manifest = """
            { "formatVersion": 1, "moduleName": "Multi\(i)", "metadata": "metadata.bin" }
            """
            let metadata = """
            symbols=1
            function _ fq=multi\(i).fn\(i) arity=0 suspend=0 sig=F0<I>
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            libDirs.append(libDir.path)
        }

        let cache = LibraryMetadataCache()

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "MultiApp", emit: .kirDump, searchPaths: libDirs)
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns,
                cache: cache
            )

            // All 3 functions should be imported
            let syntheticFns = symbols.allSymbols().filter { $0.flags.contains(.synthetic) && $0.kind == .function }
            XCTAssertEqual(syntheticFns.count, 3, "All 3 library functions should be imported")
        }

        XCTAssertEqual(cache.manifestCacheCount, 3, "All 3 manifests should be cached")
        XCTAssertEqual(cache.metadataCacheCount, 3, "All 3 metadata files should be cached")
        // All functions share F0<I>, so only 1 distinct signature
        XCTAssertEqual(cache.signatureCacheCount, 1, "All functions share same signature")
    }

    /// B6: Cached results produce semantically identical TypeIDs as non-cached
    func testCachedTypeIDsMatchNonCachedTypeIDs() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "TypeIDCheck",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        function _ fq=tid.fn1 arity=1 suspend=0 sig=F1<I,I>
        function _ fq=tid.fn2 arity=1 suspend=0 sig=F1<I,I>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        // Load WITHOUT cache
        var noCache_fn1_paramType: TypeKind?
        var noCache_fn1_returnType: TypeKind?
        var noCache_fn2_paramType: TypeKind?
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NoCacheTypeID", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns
            )
            let fn1 = symbols.allSymbols().first { interner.resolve($0.name) == "fn1" }
            let fn2 = symbols.allSymbols().first { interner.resolve($0.name) == "fn2" }
            if let fn1ID = fn1?.id, let sig = symbols.functionSignature(for: fn1ID) {
                noCache_fn1_paramType = types.kind(of: sig.parameterTypes[0])
                noCache_fn1_returnType = types.kind(of: sig.returnType)
            }
            if let fn2ID = fn2?.id, let sig = symbols.functionSignature(for: fn2ID) {
                noCache_fn2_paramType = types.kind(of: sig.parameterTypes[0])
            }
        }

        // Load WITH cache
        let cache = LibraryMetadataCache()
        var cached_fn1_paramType: TypeKind?
        var cached_fn1_returnType: TypeKind?
        var cached_fn2_paramType: TypeKind?
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "CachedTypeID", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns,
                cache: cache
            )
            let fn1 = symbols.allSymbols().first { interner.resolve($0.name) == "fn1" }
            let fn2 = symbols.allSymbols().first { interner.resolve($0.name) == "fn2" }
            if let fn1ID = fn1?.id, let sig = symbols.functionSignature(for: fn1ID) {
                cached_fn1_paramType = types.kind(of: sig.parameterTypes[0])
                cached_fn1_returnType = types.kind(of: sig.returnType)
            }
            if let fn2ID = fn2?.id, let sig = symbols.functionSignature(for: fn2ID) {
                cached_fn2_paramType = types.kind(of: sig.parameterTypes[0])
            }
        }

        // Compare TypeKinds (not raw TypeID values, since those are per-TypeSystem)
        XCTAssertEqual(noCache_fn1_paramType, cached_fn1_paramType, "fn1 param type should match")
        XCTAssertEqual(noCache_fn1_returnType, cached_fn1_returnType, "fn1 return type should match")
        XCTAssertEqual(noCache_fn2_paramType, cached_fn2_paramType, "fn2 param type should match")
        XCTAssertEqual(noCache_fn1_paramType, .primitive(.int, .nonNull))
    }

    /// B7: Suspend functions work with cache
    func testSuspendFunctionSignatureCachedCorrectly() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "SuspendTest",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        function _ fq=susp.fetch arity=1 suspend=1 sig=SF1<I,I>
        function _ fq=susp.process arity=1 suspend=0 sig=F1<I,I>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SuspendApp", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns,
                cache: cache
            )

            let fetchSym = symbols.allSymbols().first { interner.resolve($0.name) == "fetch" && $0.kind == .function }
            let processSym = symbols.allSymbols().first { interner.resolve($0.name) == "process" && $0.kind == .function }
            XCTAssertNotNil(fetchSym)
            XCTAssertNotNil(processSym)
            XCTAssertTrue(fetchSym!.flags.contains(.suspendFunction), "fetch should be marked suspend")
            XCTAssertFalse(processSym!.flags.contains(.suspendFunction), "process should NOT be marked suspend")

            // Verify suspend function signature
            if let fetchID = fetchSym?.id {
                let sig = symbols.functionSignature(for: fetchID)
                XCTAssertNotNil(sig)
                XCTAssertTrue(sig!.isSuspend)
            }

            // SF1<I,I> and F1<I,I> should be two distinct signatures
            XCTAssertEqual(cache.signatureCacheCount, 2, "Suspend and non-suspend signatures should be distinct")
        }
    }

    /// B8: Nullable type signatures cached correctly
    func testNullableTypeSignatureCachedCorrectly() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NullableTest",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        property _ fq=nullable.x sig=Q<I>
        property _ fq=nullable.y sig=I
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NullableApp", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPassPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: &inlineFns,
                cache: cache
            )

            let xSym = symbols.allSymbols().first { interner.resolve($0.name) == "x" && $0.kind == .property }
            let ySym = symbols.allSymbols().first { interner.resolve($0.name) == "y" && $0.kind == .property }
            XCTAssertNotNil(xSym)
            XCTAssertNotNil(ySym)

            if let xID = xSym?.id, let xType = symbols.propertyType(for: xID) {
                XCTAssertEqual(types.kind(of: xType), .primitive(.int, .nullable), "Q<I> should be nullable Int")
            }
            if let yID = ySym?.id, let yType = symbols.propertyType(for: yID) {
                XCTAssertEqual(types.kind(of: yType), .primitive(.int, .nonNull), "I should be non-null Int")
            }

            // Q<I> and I should be two distinct signatures
            XCTAssertEqual(cache.signatureCacheCount, 2, "Q<I> and I should be distinct cache entries")
        }
    }
}
