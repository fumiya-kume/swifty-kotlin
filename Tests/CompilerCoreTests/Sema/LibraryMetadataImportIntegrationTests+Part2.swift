import Foundation
import XCTest
@testable import CompilerCore


extension LibraryMetadataImportIntegrationTests {
    func testLibraryImportRestoresFunctionAndPropertyTypeSignatures() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtTyped",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        function _ fq=ext.id arity=1 suspend=0 sig=F1<I,I>
        property _ fq=ext.answer sig=I
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "TypedImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ext = ctx.interner.intern("ext")
            let idName = ctx.interner.intern("id")
            let answerName = ctx.interner.intern("answer")

            let functionSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, idName]).first)
            let propertySymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, answerName]).first)
            let functionSignature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
            let propertyType = try XCTUnwrap(sema.symbols.propertyType(for: propertySymbol))

            XCTAssertEqual(functionSignature.parameterTypes.count, 1)
            XCTAssertEqual(functionSignature.isSuspend, false)
            XCTAssertEqual(sema.types.kind(of: functionSignature.parameterTypes[0]), .primitive(.int, .nonNull))
            XCTAssertEqual(sema.types.kind(of: functionSignature.returnType), .primitive(.int, .nonNull))
            XCTAssertEqual(sema.types.kind(of: propertyType), .primitive(.int, .nonNull))
        }
    }

    func testLibraryImportRestoresExplicitNominalLayoutSlotsAndOffsets() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtLayout",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=4
        interface _ fq=ext.Face
        class _ fq=ext.Box fields=1 layoutWords=3 vtable=1 itable=1 fieldOffsets=ext.Box.value@2 vtableSlots=ext.Box.get#0#0@0 itableSlots=ext.Face@0
        function _ fq=ext.Box.get arity=0 suspend=0 sig=F0<I>
        property _ fq=ext.Box.value sig=I
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LayoutImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ext = ctx.interner.intern("ext")
            let box = ctx.interner.intern("Box")
            let face = ctx.interner.intern("Face")
            let get = ctx.interner.intern("get")
            let value = ctx.interner.intern("value")

            let boxSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, box]).first)
            let faceSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, face]).first)
            let getSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, box, get]).first)
            let valueSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, box, value]).first)
            let layout = try XCTUnwrap(sema.symbols.nominalLayout(for: boxSymbol))

            XCTAssertEqual(layout.fieldOffsets[valueSymbol], 2)
            XCTAssertEqual(layout.vtableSlots[getSymbol], 0)
            XCTAssertEqual(layout.itableSlots[faceSymbol], 0)
            XCTAssertEqual(layout.vtableSize, 1)
            XCTAssertEqual(layout.itableSize, 1)
        }
    }

    func testLibraryImportReportsMetadataInconsistencyDiagnostics() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtBroken",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        class _ fq=ext.Box vtable=1 vtableSlots=ext.Box.get#0#0@1,ext.Box.missing#0#0@0
        function _ fq=ext.Box.get arity=0 suspend=0 sig=broken
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BrokenImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let codes = Set(ctx.diagnostics.diagnostics.map(\.code))
            XCTAssertTrue(codes.contains("KSWIFTK-LIB-0003"))
            XCTAssertTrue(codes.contains("KSWIFTK-LIB-0004"))
            XCTAssertTrue(codes.contains("KSWIFTK-LIB-0005"))
        }
    }

    func testWildcardImportResolvesKklibSymbols() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "WildcardLib",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=3
        package _ fq=wc.util
        function _ fq=wc.util.helper arity=1 sig=F1<I,I>
        class _ fq=wc.util.Widget
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import wc.util.*
        fun main() = helper(1)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "WildcardApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let helperSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "helper" &&
                symbol.kind == .function &&
                symbol.flags.contains(.synthetic) &&
                symbol.fqName.map { ctx.interner.resolve($0) } == ["wc", "util", "helper"]
            }
            XCTAssertNotNil(helperSymbol, "Wildcard import should resolve library function 'helper'")

            let widgetSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Widget" &&
                symbol.kind == .class &&
                symbol.flags.contains(.synthetic) &&
                symbol.fqName.map { ctx.interner.resolve($0) } == ["wc", "util", "Widget"]
            }
            XCTAssertNotNil(widgetSymbol, "Wildcard import should resolve library class 'Widget'")
            XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-SEMA") })
        }
    }

    func testDefaultImportResolvesKklibSymbolsFromStdlibPackages() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "StdlibStub",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=3
        package _ fq=kotlin
        package _ fq=kotlin.collections
        function _ fq=kotlin.collections.listOf arity=0 sig=F0<A>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        fun main() = listOf()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "DefaultImportApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let listOfSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "listOf" &&
                symbol.kind == .function &&
                symbol.flags.contains(.synthetic) &&
                symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "collections", "listOf"]
            }
            XCTAssertNotNil(listOfSymbol, "Default import should resolve library function 'listOf' from kotlin.collections")
            XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-SEMA") })
        }
    }

    func testExplicitImportStillWorksAlongsideWildcardForKklibSymbols() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "MixedLib",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=4
        package _ fq=mix.api
        function _ fq=mix.api.alpha arity=0
        function _ fq=mix.api.beta arity=0
        class _ fq=mix.api.Gamma
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import mix.api.alpha
        import mix.api.*
        fun main() = alpha()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MixedImportApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let alphaSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "alpha" &&
                symbol.kind == .function &&
                symbol.flags.contains(.synthetic) &&
                symbol.fqName.map { ctx.interner.resolve($0) } == ["mix", "api", "alpha"]
            }
            XCTAssertNotNil(alphaSymbol, "Explicit import should resolve library function 'alpha'")

            let betaSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "beta" &&
                symbol.kind == .function &&
                symbol.flags.contains(.synthetic) &&
                symbol.fqName.map { ctx.interner.resolve($0) } == ["mix", "api", "beta"]
            }
            XCTAssertNotNil(betaSymbol, "Wildcard import should resolve library function 'beta'")

            let gammaSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Gamma" &&
                symbol.kind == .class &&
                symbol.flags.contains(.synthetic) &&
                symbol.fqName.map { ctx.interner.resolve($0) } == ["mix", "api", "Gamma"]
            }
            XCTAssertNotNil(gammaSymbol, "Wildcard import should resolve library class 'Gamma'")
            XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-SEMA") })
        }
    }

}
