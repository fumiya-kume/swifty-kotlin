import Foundation
import XCTest
@testable import CompilerCore

final class LibraryMetadataCoverageTests: XCTestCase {
    func testSemaLoadsSymbolsFromKklibSearchPath() throws {
        let librarySource = """
        package extdemo
        fun plus(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus
            fun main() = plus(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)

                let sema = try XCTUnwrap(appCtx.sema)
                let importedPlus = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus" &&
                    symbol.kind == .function &&
                    symbol.flags.contains(.synthetic)
                }
                XCTAssertNotNil(importedPlus)
                XCTAssertFalse(appCtx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
            }
        }
    }

    func testInlineLoweringExpandsImportedInlineFunctionFromKklib() throws {
        let librarySource = """
        package extdemo
        inline fun plus1(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus1
            fun main() = plus1(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)

                let sema = try XCTUnwrap(appCtx.sema)
                let importedInline = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus1" &&
                    symbol.kind == .function &&
                    symbol.flags.contains(.inlineFunction)
                }
                XCTAssertNotNil(importedInline)
                XCTAssertFalse(sema.importedInlineFunctions.isEmpty)

                let kir = try XCTUnwrap(appCtx.kir)
                let mainFunction = try XCTUnwrap(
                    kir.arena.declarations.compactMap({ decl -> KIRFunction? in
                        guard case .function(let function) = decl else { return nil }
                        return appCtx.interner.resolve(function.name) == "main" ? function : nil
                    }).first,
                    "Expected lowered main function"
                )

                let calls = mainFunction.body.compactMap { instruction -> String? in
                    guard case .call(_, let callee, _, _, _, _) = instruction else {
                        return nil
                    }
                    return appCtx.interner.resolve(callee)
                }
                XCTAssertFalse(calls.contains("plus1"))
                XCTAssertTrue(calls.contains("kk_op_add"))
            }
        }
    }

    func testSemaSynthesizesNominalLayoutsAndLibraryMetadataContainsLayoutFields() throws {
        let source = """
        package layoutdemo
        class Base
        class Derived: Base
        """

        try withTemporaryFile(contents: source) { path in
            let semaCtx = makeCompilationContext(inputs: [path], moduleName: "LayoutSema", emit: .kirDump)
            try runToKIR(semaCtx)

            let sema = try XCTUnwrap(semaCtx.sema)
            let base = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                semaCtx.interner.resolve(symbol.name) == "Base" && symbol.kind == .class
            }))
            let derived = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                semaCtx.interner.resolve(symbol.name) == "Derived" && symbol.kind == .class
            }))

            let baseLayout = sema.symbols.nominalLayout(for: base.id)
            let derivedLayout = sema.symbols.nominalLayout(for: derived.id)
            XCTAssertNotNil(baseLayout)
            XCTAssertNotNil(derivedLayout)
            XCTAssertEqual(baseLayout?.objectHeaderWords, 2)
            XCTAssertGreaterThanOrEqual(baseLayout?.instanceSizeWords ?? 0, 2)
            XCTAssertEqual(derivedLayout?.superClass, base.id)

            let libBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libCtx = makeCompilationContext(
                inputs: [path],
                moduleName: "LayoutLib",
                emit: .library,
                outputPath: libBase
            )
            try runToKIR(libCtx)
            try LoweringPhase().run(libCtx)
            try CodegenPhase().run(libCtx)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
            XCTAssertTrue(metadata.contains("layoutWords="))
            XCTAssertTrue(metadata.contains("vtable="))
            XCTAssertTrue(metadata.contains("itable="))
            XCTAssertTrue(metadata.contains("superFq=layoutdemo.Base"))
        }
    }

    func testSemaAllocatesVtableSlotsFromImportedNominalMetadata() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtMeta",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        class _ fq=ext.C
        function _ fq=ext.C.m arity=0 suspend=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "VTableImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let classSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                ctx.interner.resolve(symbol.name) == "C" && symbol.kind == .class
            }))
            let layout = sema.symbols.nominalLayout(for: classSymbol.id)
            XCTAssertNotNil(layout)
            XCTAssertEqual(layout?.vtableSlots.count, 1)
            XCTAssertEqual(layout?.vtableSize, 1)
            XCTAssertEqual(layout?.itableSlots.count, 0)
            XCTAssertEqual(layout?.itableSize, 0)
        }
    }

    func testSemaReusesVtableSlotForImportedOverrideMethods() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtMetaOverride",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=4
        class _ fq=ext.Base fields=0 layoutWords=3 vtable=1 itable=0
        function _ fq=ext.Base.m arity=0 suspend=0
        class _ fq=ext.Derived superFq=ext.Base fields=0 layoutWords=3 vtable=1 itable=0
        function _ fq=ext.Derived.m arity=0 suspend=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "VTableOverrideImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let baseClass = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base")]).first)
            let derivedClass = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Derived")]).first)
            let baseMethod = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base"), ctx.interner.intern("m")]).first)
            let derivedMethod = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Derived"), ctx.interner.intern("m")]).first)

            let baseLayout = try XCTUnwrap(sema.symbols.nominalLayout(for: baseClass))
            let derivedLayout = try XCTUnwrap(sema.symbols.nominalLayout(for: derivedClass))
            XCTAssertEqual(derivedLayout.superClass, baseClass)
            XCTAssertEqual(baseLayout.vtableSize, 1)
            XCTAssertEqual(derivedLayout.vtableSize, 1)
            XCTAssertEqual(derivedLayout.vtableSlots[baseMethod], derivedLayout.vtableSlots[derivedMethod])
        }
    }

    func testSemaInheritsImportedFieldLayoutFromMetadataHints() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtLayoutHint",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        class _ fq=ext.Base fields=1 layoutWords=4 vtable=0 itable=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        class Derived: ext.Base
        fun main() = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LayoutHintImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let baseClass = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base")]).first)
            let derivedClass = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Derived")]).first)
            let baseLayout = try XCTUnwrap(sema.symbols.nominalLayout(for: baseClass))
            let derivedLayout = try XCTUnwrap(sema.symbols.nominalLayout(for: derivedClass))

            XCTAssertEqual(baseLayout.instanceFieldCount, 1)
            XCTAssertEqual(baseLayout.instanceSizeWords, 4)
            XCTAssertEqual(derivedLayout.superClass, baseClass)
            XCTAssertEqual(derivedLayout.instanceFieldCount, 1)
            XCTAssertEqual(derivedLayout.instanceSizeWords, 4)
        }
    }

    func testLibraryMetadataExportsTypeSignatures() throws {
        let source = """
        package metaexport
        fun id(v: Int): Int = v
        val answer: Int = 42
        """
        try withTemporaryFile(contents: source) { path in
            let libBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MetaExport",
                emit: .library,
                outputPath: libBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
            XCTAssertTrue(metadata.contains("function "))
            XCTAssertTrue(metadata.contains("property "))
            XCTAssertTrue(metadata.contains("sig=F1<I,I>"))
            XCTAssertTrue(metadata.contains("sig=I"))
        }
    }

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

    // MARK: - Manifest Schema Validation Tests

    func testManifestMissingFormatVersionEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "moduleName": "NoVersion",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=nv.foo arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoVersionApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0010", in: ctx)
            let noSymbols = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "foo" && symbol.flags.contains(.synthetic)
            }
            XCTAssertFalse(noSymbols ?? false)
        }
    }

    func testManifestUnsupportedFormatVersionEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 99,
          "moduleName": "BadVersion",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=bv.bar arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadVersionApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0010", in: ctx)
        }
    }

    func testManifestMissingModuleNameEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=nm.baz arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoModuleNameApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0011", in: ctx)
        }
    }

    func testManifestEmptyModuleNameEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=em.qux arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EmptyModuleNameApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0011", in: ctx)
        }
    }

    func testManifestUnsupportedKotlinLanguageVersionEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "BadLang",
          "kotlinLanguageVersion": "1.9.0",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=bl.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadLangApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0012", in: ctx)
        }
    }

    func testManifestIncompatibleTargetEmitsErrorAndSkipsLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "WrongTarget",
          "kotlinLanguageVersion": "2.3.10",
          "target": "fake-unknown-invalid",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=wt.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "WrongTargetApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0013", in: ctx)
            let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "fn" && symbol.flags.contains(.synthetic)
            }
            XCTAssertFalse(hasImported ?? false)
        }
    }

    func testManifestCompatibleTargetDoesNotEmitTargetError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "GoodTarget",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=gt.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "GoodTargetApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertNoDiagnostic("KSWIFTK-LIB-0010", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0011", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0012", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0013", in: ctx)
        }
    }

    func testManifestMissingMetadataFileEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NoMeta",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "nonexistent.bin"
        }
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoMetaApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0014", in: ctx)
        }
    }

    func testManifestMissingObjectFileEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "MissingObj",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "objects": ["objects/missing.o"],
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=mo.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MissingObjApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let pathWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0014" && $0.severity == .warning
            }
            XCTAssertFalse(pathWarnings.isEmpty)
        }
    }

    func testManifestMissingInlineKIRDirEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "MissingInline",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "metadata.bin",
          "inlineKIRDir": "nonexistent-dir"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=mi.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MissingInlineApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let pathWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0014" && $0.severity == .warning
            }
            XCTAssertFalse(pathWarnings.isEmpty)
        }
    }

    // MARK: - P5-43 Regression: wildcard/default import with .kklib symbols

    func testWildcardImportResolvesKklibSymbolInScope() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ScopeLib",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=3
        package _ fq=sc.util
        function _ fq=sc.util.compute arity=1 sig=F1<I,I>
        class _ fq=sc.util.Engine
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import sc.util.*
        fun main(): Int = compute(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ScopeApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            // Verify the symbol is present
            let computeSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "compute" &&
                symbol.kind == .function &&
                symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(computeSymbol, "Wildcard import should make library function 'compute' available")

            // Verify no SEMA/TYPE diagnostics (proves the symbol resolved in scope)
            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "Wildcard import should resolve library function without errors: \(semaErrors.map(\.code))")
        }
    }

    func testDefaultImportResolvesKklibSymbolInScope() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "StdlibDefault",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=3
        package _ fq=kotlin
        package _ fq=kotlin.text
        function _ fq=kotlin.text.isBlank arity=1 sig=F1<Lkotlin_String;,Z>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        fun main(): Boolean = isBlank("")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "DefaultScopeApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let isBlankSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "isBlank" &&
                symbol.kind == .function &&
                symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(isBlankSymbol, "Default import should make library function 'isBlank' from kotlin.text available")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "Default import should resolve library function without errors: \(semaErrors.map(\.code))")
        }
    }

    func testWildcardImportWithoutExplicitPackageRecordInMetadata() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NoPackageRecord",
          "metadata": "metadata.bin"
        }
        """
        // Metadata has no explicit package records; packages should be synthesized
        let metadata = """
        symbols=2
        function _ fq=np.api.doWork arity=0
        class _ fq=np.api.Worker
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import np.api.*
        fun main() = doWork()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoPackageApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            // Verify synthetic package was created
            let packageSymbol = sema.symbols.allSymbols().first { symbol in
                symbol.kind == .package &&
                symbol.fqName.map { ctx.interner.resolve($0) } == ["np", "api"]
            }
            XCTAssertNotNil(packageSymbol, "Synthetic package 'np.api' should be created even without explicit package record")

            let doWorkSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "doWork" &&
                symbol.kind == .function &&
                symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(doWorkSymbol, "Wildcard import should resolve function from synthesized package")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "No SEMA errors expected: \(semaErrors.map(\.code))")
        }
    }

    func testMultipleKklibWildcardImportsCoexist() throws {
        let fm = FileManager.default

        // Create first library
        let baseDir1 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir1 = baseDir1.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir1, withIntermediateDirectories: true)

        let manifest1 = """
        {
          "formatVersion": 1,
          "moduleName": "LibA",
          "metadata": "metadata.bin"
        }
        """
        let metadata1 = """
        symbols=2
        package _ fq=lib.a
        function _ fq=lib.a.funcA arity=0
        """
        try manifest1.write(to: libDir1.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata1.write(to: libDir1.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        // Create second library
        let baseDir2 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir2 = baseDir2.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir2, withIntermediateDirectories: true)

        let manifest2 = """
        {
          "formatVersion": 1,
          "moduleName": "LibB",
          "metadata": "metadata.bin"
        }
        """
        let metadata2 = """
        symbols=2
        package _ fq=lib.b
        function _ fq=lib.b.funcB arity=0
        """
        try manifest2.write(to: libDir2.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata2.write(to: libDir2.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import lib.a.*
        import lib.b.*
        fun main() {
            funcA()
            funcB()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MultiLibApp",
                emit: .kirDump,
                searchPaths: [libDir1.path, libDir2.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            let funcA = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "funcA" && symbol.flags.contains(.synthetic)
            }
            let funcB = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "funcB" && symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(funcA, "funcA from lib.a should be resolved via wildcard import")
            XCTAssertNotNil(funcB, "funcB from lib.b should be resolved via wildcard import")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "No SEMA errors expected with multiple library wildcard imports: \(semaErrors.map(\.code))")
        }
    }

    func testPackageSymbolCreatedEvenWhenNonPackageSymbolExistsAtSamePath() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "CoexistLib",
          "metadata": "metadata.bin"
        }
        """
        // Library has both a class 'cx.util' and functions under package 'cx.util'
        let metadata = """
        symbols=3
        class _ fq=cx.util
        function _ fq=cx.util.process arity=0
        function _ fq=cx.util.transform arity=1 sig=F1<I,I>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import cx.util.*
        fun main() = process()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CoexistApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            // Verify the package symbol was created despite the class 'cx.util' existing
            let packageSymbol = sema.symbols.allSymbols().first { symbol in
                symbol.kind == .package &&
                symbol.fqName.map { ctx.interner.resolve($0) } == ["cx", "util"]
            }
            XCTAssertNotNil(packageSymbol, "Package 'cx.util' should be created even when class 'cx.util' exists")

            let processSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "process" &&
                symbol.kind == .function &&
                symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(processSymbol, "Wildcard import should resolve 'process' even when non-package symbol coexists at package path")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "No SEMA errors expected: \(semaErrors.map(\.code))")
        }
    }

    func testDefaultImportFromMultipleStdlibPackagesInKklib() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "StdlibMulti",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=5
        package _ fq=kotlin
        package _ fq=kotlin.collections
        package _ fq=kotlin.text
        function _ fq=kotlin.collections.listOf arity=0 sig=F0<A>
        function _ fq=kotlin.text.trim arity=1 sig=F1<Lkotlin_String;,Lkotlin_String;>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        fun main() {
            listOf()
            trim("")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MultiStdlibApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            let listOfSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "listOf" && symbol.flags.contains(.synthetic)
            }
            let trimSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "trim" && symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(listOfSymbol, "Default import should resolve 'listOf' from kotlin.collections")
            XCTAssertNotNil(trimSymbol, "Default import should resolve 'trim' from kotlin.text")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "No SEMA errors expected: \(semaErrors.map(\.code))")
        }
    }
}
