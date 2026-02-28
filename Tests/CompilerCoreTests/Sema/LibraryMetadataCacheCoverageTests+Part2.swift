import Foundation
import XCTest
@testable import CompilerCore


extension LibraryMetadataCacheCoverageTests {
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
}
