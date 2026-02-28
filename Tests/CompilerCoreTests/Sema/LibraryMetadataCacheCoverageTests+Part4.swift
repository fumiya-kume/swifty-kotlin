import Foundation
import XCTest
@testable import CompilerCore



extension LibraryMetadataCacheCoverageTests {
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
            DataFlowSemaPhase().loadImportedLibrarySymbols(
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
