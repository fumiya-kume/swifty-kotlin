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
                    guard case .call(_, let callee, _, _, _, _, _) = instruction else {
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

    // MARK: - MetadataSerializer Round-Trip Tests

    func testMetadataEncoderDecoderRoundTripForFunctionRecord() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_ext_id",
            fqName: "ext.id",
            arity: 1,
            isSuspend: false,
            isInline: true,
            typeSignature: "F1<I,I>",
            externalLinkName: "_ext_id"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        XCTAssertEqual(decoded.count, 1)
        let r = decoded[0]
        XCTAssertEqual(r.kind, .function)
        XCTAssertEqual(r.mangledName, "_kk_ext_id")
        XCTAssertEqual(r.fqName, "ext.id")
        XCTAssertEqual(r.arity, 1)
        XCTAssertEqual(r.isSuspend, false)
        XCTAssertEqual(r.isInline, true)
        XCTAssertEqual(r.typeSignature, "F1<I,I>")
        XCTAssertEqual(r.externalLinkName, "_ext_id")
    }

    func testMetadataEncoderDecoderRoundTripForClassWithLayout() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_ext_Box",
            fqName: "ext.Box",
            declaredFieldCount: 2,
            declaredInstanceSizeWords: 4,
            declaredVtableSize: 1,
            declaredItableSize: 1,
            superFQName: "ext.Base",
            fieldOffsets: "ext.Box.x@2,ext.Box.y@3",
            vtableSlots: "ext.Box.get#0#0@0",
            itableSlots: "ext.IFace@0"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        XCTAssertEqual(decoded.count, 1)
        let r = decoded[0]
        XCTAssertEqual(r.kind, .class)
        XCTAssertEqual(r.fqName, "ext.Box")
        XCTAssertEqual(r.declaredFieldCount, 2)
        XCTAssertEqual(r.declaredInstanceSizeWords, 4)
        XCTAssertEqual(r.declaredVtableSize, 1)
        XCTAssertEqual(r.declaredItableSize, 1)
        XCTAssertEqual(r.superFQName, "ext.Base")
        XCTAssertEqual(r.fieldOffsets, "ext.Box.x@2,ext.Box.y@3")
        XCTAssertEqual(r.vtableSlots, "ext.Box.get#0#0@0")
        XCTAssertEqual(r.itableSlots, "ext.IFace@0")
    }

    func testMetadataEncoderDecoderRoundTripForDataClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_data_Point",
            fqName: "demo.Point",
            isDataClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("dataClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertTrue(decoded[0].isDataClass)
        XCTAssertFalse(decoded[0].isSealedClass)
    }

    func testMetadataEncoderDecoderRoundTripForSealedClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_sealed_Shape",
            fqName: "demo.Shape",
            isSealedClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("sealedClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertFalse(decoded[0].isDataClass)
        XCTAssertTrue(decoded[0].isSealedClass)
    }

    func testMetadataEncoderDecoderRoundTripForAnnotations() {
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["Use newMethod instead"],
                useSiteTarget: nil
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.jvm.JvmStatic",
                arguments: [],
                useSiteTarget: "get"
            ),
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_old",
            fqName: "demo.oldMethod",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("annotations="))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].annotations.count, 2)
        XCTAssertEqual(decoded[0].annotations[0].annotationFQName, "kotlin.Deprecated")
        XCTAssertEqual(decoded[0].annotations[0].arguments, ["Use newMethod instead"])
        XCTAssertNil(decoded[0].annotations[0].useSiteTarget)
        XCTAssertEqual(decoded[0].annotations[1].annotationFQName, "kotlin.jvm.JvmStatic")
        XCTAssertEqual(decoded[0].annotations[1].arguments, [])
        XCTAssertEqual(decoded[0].annotations[1].useSiteTarget, "get")
    }

    func testMetadataEncoderDecoderRoundTripForDataAndSealedBothSet() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_ext_Weird",
            fqName: "ext.Weird",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 0,
            isDataClass: true,
            isSealedClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("dataClass=1"))
        XCTAssertTrue(serialized.contains("sealedClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .class)
        XCTAssertEqual(decoded[0].fqName, "ext.Weird")
        XCTAssertTrue(decoded[0].isDataClass)
        XCTAssertTrue(decoded[0].isSealedClass)
    }

    func testMetadataDecoderHandlesLegacyFormatWithoutNewFields() {
        // Simulate old metadata without dataClass/sealedClass/annotations fields
        let legacy = """
        symbols=1
        class _kk_ext_C fq=ext.C fields=0 layoutWords=3 vtable=0 itable=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(legacy)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .class)
        XCTAssertEqual(decoded[0].fqName, "ext.C")
        XCTAssertFalse(decoded[0].isDataClass)
        XCTAssertFalse(decoded[0].isSealedClass)
        XCTAssertTrue(decoded[0].annotations.isEmpty)
    }

    func testMetadataRoundTripMultipleRecords() {
        let records = [
            MetadataRecord(
                kind: .class,
                mangledName: "_kk_Point",
                fqName: "demo.Point",
                declaredFieldCount: 2,
                declaredInstanceSizeWords: 4,
                isDataClass: true,
                annotations: [
                    MetadataAnnotationRecord(annotationFQName: "kotlin.Serializable")
                ]
            ),
            MetadataRecord(
                kind: .function,
                mangledName: "_kk_demo_greet",
                fqName: "demo.greet",
                arity: 1,
                isSuspend: true,
                typeSignature: "F1<S,U>"
            ),
            MetadataRecord(
                kind: .property,
                mangledName: "_kk_demo_name",
                fqName: "demo.name",
                typeSignature: "S"
            ),
        ]
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize(records)
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        XCTAssertEqual(decoded.count, 3)

        XCTAssertEqual(decoded[0].kind, .class)
        XCTAssertEqual(decoded[0].fqName, "demo.Point")
        XCTAssertTrue(decoded[0].isDataClass)
        XCTAssertEqual(decoded[0].annotations.count, 1)
        XCTAssertEqual(decoded[0].annotations[0].annotationFQName, "kotlin.Serializable")

        XCTAssertEqual(decoded[1].kind, .function)
        XCTAssertEqual(decoded[1].fqName, "demo.greet")
        XCTAssertEqual(decoded[1].arity, 1)
        XCTAssertTrue(decoded[1].isSuspend)
        XCTAssertEqual(decoded[1].typeSignature, "F1<S,U>")

        XCTAssertEqual(decoded[2].kind, .property)
        XCTAssertEqual(decoded[2].fqName, "demo.name")
        XCTAssertEqual(decoded[2].typeSignature, "S")
    }

    func testMetadataImportRestoresDataClassFlagViaLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtDataClass",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        class _kk_Point fq=ext.Point fields=2 layoutWords=4 vtable=0 itable=0 dataClass=1
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "DataClassImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let pointSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Point" && symbol.kind == .class
            }
            XCTAssertNotNil(pointSymbol)
            XCTAssertTrue(pointSymbol?.flags.contains(.dataType) ?? false)
            XCTAssertFalse(pointSymbol?.flags.contains(.sealedType) ?? true)
        }
    }

    // MARK: - MetadataDecoder.symbolKindFromMetadata Unit Tests

    func testSymbolKindFromMetadataReturnsCorrectKindForAllTokens() {
        let decoder = MetadataDecoder()
        XCTAssertEqual(decoder.symbolKindFromMetadata("package"), .package)
        XCTAssertEqual(decoder.symbolKindFromMetadata("class"), .class)
        XCTAssertEqual(decoder.symbolKindFromMetadata("interface"), .interface)
        XCTAssertEqual(decoder.symbolKindFromMetadata("object"), .object)
        XCTAssertEqual(decoder.symbolKindFromMetadata("enumClass"), .enumClass)
        XCTAssertEqual(decoder.symbolKindFromMetadata("annotationClass"), .annotationClass)
        XCTAssertEqual(decoder.symbolKindFromMetadata("typeAlias"), .typeAlias)
        XCTAssertEqual(decoder.symbolKindFromMetadata("function"), .function)
        XCTAssertEqual(decoder.symbolKindFromMetadata("constructor"), .constructor)
        XCTAssertEqual(decoder.symbolKindFromMetadata("property"), .property)
        XCTAssertEqual(decoder.symbolKindFromMetadata("field"), .field)
        XCTAssertEqual(decoder.symbolKindFromMetadata("typeParameter"), .typeParameter)
        XCTAssertEqual(decoder.symbolKindFromMetadata("valueParameter"), .valueParameter)
        XCTAssertEqual(decoder.symbolKindFromMetadata("local"), .local)
        XCTAssertEqual(decoder.symbolKindFromMetadata("label"), .label)
    }

    func testSymbolKindFromMetadataReturnsNilForUnknownToken() {
        let decoder = MetadataDecoder()
        XCTAssertNil(decoder.symbolKindFromMetadata(""))
        XCTAssertNil(decoder.symbolKindFromMetadata("unknown"))
        XCTAssertNil(decoder.symbolKindFromMetadata("CLASS"))
        XCTAssertNil(decoder.symbolKindFromMetadata("Function"))
        XCTAssertNil(decoder.symbolKindFromMetadata("backingField"))
    }

    // MARK: - MetadataDecoder Edge Cases

    func testMetadataDecoderReturnsEmptyForEmptyInput() {
        let decoder = MetadataDecoder()
        XCTAssertEqual(decoder.decode("").count, 0)
    }

    func testMetadataDecoderReturnsEmptyForOnlyHeader() {
        let decoder = MetadataDecoder()
        XCTAssertEqual(decoder.decode("symbols=5\n").count, 0)
    }

    func testMetadataDecoderReturnsEmptyForWhitespaceOnly() {
        let decoder = MetadataDecoder()
        XCTAssertEqual(decoder.decode("   \n  \n").count, 0)
    }

    func testMetadataDecoderSkipsLinesWithUnknownKind() {
        let metadata = """
        symbols=2
        unknownKind _kk_foo fq=demo.Foo
        function _kk_bar fq=demo.bar arity=0 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].fqName, "demo.bar")
    }

    func testMetadataDecoderSkipsLinesWithoutFqField() {
        let metadata = """
        symbols=1
        function _kk_bar arity=0 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        XCTAssertEqual(decoded.count, 0)
    }

    func testMetadataDecoderSkipsLinesWithEmptyFqField() {
        let metadata = """
        symbols=1
        function _kk_bar fq= arity=0 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        XCTAssertEqual(decoded.count, 0)
    }

    func testMetadataDecoderIgnoresTokensWithoutEqualsSign() {
        // Tokens without '=' should be silently skipped (except kind and mangledName)
        let metadata = """
        symbols=1
        function _kk_bar fq=demo.bar randomtoken arity=2 suspend=1 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].arity, 2)
        XCTAssertTrue(decoded[0].isSuspend)
    }

    func testMetadataDecoderIgnoresUnknownKeyValuePairs() {
        let metadata = """
        symbols=1
        class _kk_Foo fq=demo.Foo futureKey=futureValue fields=1 layoutWords=2
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].fqName, "demo.Foo")
        XCTAssertEqual(decoded[0].declaredFieldCount, 1)
    }

    // MARK: - MetadataEncoder Edge Cases

    func testMetadataEncoderSerializeEmptyRecordsArray() {
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([])
        XCTAssertEqual(serialized, "symbols=0\n")
    }

    func testMetadataEncoderDoesNotEmitDataClassWhenFalse() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_Foo",
            fqName: "demo.Foo"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertFalse(serialized.contains("dataClass="))
        XCTAssertFalse(serialized.contains("sealedClass="))
        XCTAssertFalse(serialized.contains("annotations="))
    }

    func testMetadataEncoderDoesNotEmitAnnotationsWhenEmpty() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_foo",
            fqName: "demo.foo",
            annotations: []
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertFalse(serialized.contains("annotations="))
    }

    // MARK: - Round-Trip for Each Symbol Kind

    func testMetadataRoundTripForPropertyWithTypeSignature() {
        let record = MetadataRecord(
            kind: .property,
            mangledName: "_kk_demo_name",
            fqName: "demo.name",
            typeSignature: "S"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("sig=S"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .property)
        XCTAssertEqual(decoded[0].fqName, "demo.name")
        XCTAssertEqual(decoded[0].typeSignature, "S")
    }

    func testMetadataRoundTripForFieldWithTypeSignature() {
        let record = MetadataRecord(
            kind: .field,
            mangledName: "_kk_demo_x",
            fqName: "demo.x",
            typeSignature: "I"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("sig=I"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .field)
        XCTAssertEqual(decoded[0].typeSignature, "I")
    }

    func testMetadataRoundTripForTypeAliasWithTypeSignature() {
        let record = MetadataRecord(
            kind: .typeAlias,
            mangledName: "_kk_demo_ID",
            fqName: "demo.ID",
            typeSignature: "L"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("sig=L"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .typeAlias)
        XCTAssertEqual(decoded[0].fqName, "demo.ID")
        XCTAssertEqual(decoded[0].typeSignature, "L")
    }

    func testMetadataRoundTripForInterface() {
        let record = MetadataRecord(
            kind: .interface,
            mangledName: "_kk_demo_IFoo",
            fqName: "demo.IFoo",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 0,
            declaredVtableSize: 2,
            declaredItableSize: 0
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .interface)
        XCTAssertEqual(decoded[0].fqName, "demo.IFoo")
        XCTAssertEqual(decoded[0].declaredVtableSize, 2)
    }

    func testMetadataRoundTripForObject() {
        let record = MetadataRecord(
            kind: .object,
            mangledName: "_kk_demo_Singleton",
            fqName: "demo.Singleton",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 1
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .object)
        XCTAssertEqual(decoded[0].fqName, "demo.Singleton")
        XCTAssertEqual(decoded[0].declaredInstanceSizeWords, 1)
    }

    func testMetadataRoundTripForEnumClass() {
        let record = MetadataRecord(
            kind: .enumClass,
            mangledName: "_kk_demo_Color",
            fqName: "demo.Color",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 1,
            isSealedClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .enumClass)
        XCTAssertEqual(decoded[0].fqName, "demo.Color")
        XCTAssertTrue(decoded[0].isSealedClass)
    }

    func testMetadataRoundTripForAnnotationClass() {
        let record = MetadataRecord(
            kind: .annotationClass,
            mangledName: "_kk_demo_MyAnno",
            fqName: "demo.MyAnno",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 0
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .annotationClass)
        XCTAssertEqual(decoded[0].fqName, "demo.MyAnno")
    }

    func testMetadataRoundTripForConstructor() {
        let metadata = """
        symbols=1
        constructor _kk_demo_init fq=demo.Foo.init arity=2 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .constructor)
        XCTAssertEqual(decoded[0].fqName, "demo.Foo.init")
        XCTAssertEqual(decoded[0].arity, 2)
    }

    func testMetadataEncoderIncludesArityForConstructor() {
        let record = MetadataRecord(
            kind: .constructor,
            mangledName: "_kk_demo_Foo_init",
            fqName: "demo.Foo.init",
            arity: 2,
            isSuspend: false,
            isInline: false
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("arity=2"))
        XCTAssertTrue(serialized.contains("suspend=0"))
        XCTAssertTrue(serialized.contains("inline=0"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .constructor)
        XCTAssertEqual(decoded[0].fqName, "demo.Foo.init")
        XCTAssertEqual(decoded[0].arity, 2)
    }

    func testMetadataRoundTripForSuspendFunction() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_demo_fetch",
            fqName: "demo.fetch",
            arity: 1,
            isSuspend: true,
            isInline: false,
            typeSignature: "F1<S,U>"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("suspend=1"))
        XCTAssertTrue(serialized.contains("inline=0"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertTrue(decoded[0].isSuspend)
        XCTAssertFalse(decoded[0].isInline)
        XCTAssertEqual(decoded[0].typeSignature, "F1<S,U>")
    }

    func testMetadataRoundTripForFunctionWithExternalLinkName() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_demo_add",
            fqName: "demo.add",
            arity: 2,
            externalLinkName: "_demo_add_impl"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        XCTAssertTrue(serialized.contains("link=_demo_add_impl"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].externalLinkName, "_demo_add_impl")
    }

    // MARK: - Annotation Encoding/Decoding Edge Cases

    func testAnnotationRoundTripWithMultipleArguments() {
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["old name", "use new() instead", "WARNING"],
                useSiteTarget: nil
            )
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_old",
            fqName: "demo.old",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].annotations.count, 1)
        XCTAssertEqual(decoded[0].annotations[0].arguments.count, 3)
        XCTAssertEqual(decoded[0].annotations[0].arguments[0], "old name")
        XCTAssertEqual(decoded[0].annotations[0].arguments[1], "use new() instead")
        XCTAssertEqual(decoded[0].annotations[0].arguments[2], "WARNING")
    }

    func testAnnotationRoundTripWithSpecialCharactersInArguments() {
        // Base64 encoding should handle special characters safely
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "custom.Config",
                arguments: ["key=value", "a|b|c", "semi;colon", "space here", "emoji\u{1F600}"],
                useSiteTarget: nil
            )
        ]
        let record = MetadataRecord(
            kind: .property,
            mangledName: "_kk_cfg",
            fqName: "demo.cfg",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].annotations.count, 1)
        XCTAssertEqual(decoded[0].annotations[0].arguments.count, 5)
        XCTAssertEqual(decoded[0].annotations[0].arguments[0], "key=value")
        XCTAssertEqual(decoded[0].annotations[0].arguments[1], "a|b|c")
        XCTAssertEqual(decoded[0].annotations[0].arguments[2], "semi;colon")
        XCTAssertEqual(decoded[0].annotations[0].arguments[3], "space here")
        XCTAssertEqual(decoded[0].annotations[0].arguments[4], "emoji\u{1F600}")
    }

    func testAnnotationRoundTripWithMultipleAnnotationsOnOneSymbol() {
        let annotations = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated"),
            MetadataAnnotationRecord(annotationFQName: "kotlin.jvm.JvmStatic", useSiteTarget: "get"),
            MetadataAnnotationRecord(annotationFQName: "kotlin.Suppress", arguments: ["UNCHECKED_CAST"]),
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_foo",
            fqName: "demo.foo",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].annotations.count, 3)
        XCTAssertEqual(decoded[0].annotations[0].annotationFQName, "kotlin.Deprecated")
        XCTAssertTrue(decoded[0].annotations[0].arguments.isEmpty)
        XCTAssertNil(decoded[0].annotations[0].useSiteTarget)
        XCTAssertEqual(decoded[0].annotations[1].annotationFQName, "kotlin.jvm.JvmStatic")
        XCTAssertEqual(decoded[0].annotations[1].useSiteTarget, "get")
        XCTAssertEqual(decoded[0].annotations[2].annotationFQName, "kotlin.Suppress")
        XCTAssertEqual(decoded[0].annotations[2].arguments, ["UNCHECKED_CAST"])
    }

    func testAnnotationRecordEquatable() {
        let a = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["msg"], useSiteTarget: "get")
        let b = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["msg"], useSiteTarget: "get")
        let c = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["other"], useSiteTarget: "get")
        let d = MetadataAnnotationRecord(annotationFQName: "kotlin.Suppress", arguments: ["msg"], useSiteTarget: "get")
        let e = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["msg"], useSiteTarget: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
        XCTAssertNotEqual(a, e)
    }

    // MARK: - MetadataRecord Default Values

    func testMetadataRecordDefaultInitializerValues() {
        let record = MetadataRecord(kind: .function)
        XCTAssertEqual(record.kind, .function)
        XCTAssertEqual(record.mangledName, "")
        XCTAssertEqual(record.fqName, "")
        XCTAssertEqual(record.arity, 0)
        XCTAssertFalse(record.isSuspend)
        XCTAssertFalse(record.isInline)
        XCTAssertNil(record.typeSignature)
        XCTAssertNil(record.externalLinkName)
        XCTAssertNil(record.declaredFieldCount)
        XCTAssertNil(record.declaredInstanceSizeWords)
        XCTAssertNil(record.declaredVtableSize)
        XCTAssertNil(record.declaredItableSize)
        XCTAssertNil(record.superFQName)
        XCTAssertNil(record.fieldOffsets)
        XCTAssertNil(record.vtableSlots)
        XCTAssertNil(record.itableSlots)
        XCTAssertFalse(record.isDataClass)
        XCTAssertFalse(record.isSealedClass)
        XCTAssertTrue(record.annotations.isEmpty)
    }

    // MARK: - Serialize Output Format Verification

    func testMetadataSerializeSymbolsHeaderLine() {
        let records = [
            MetadataRecord(kind: .function, mangledName: "_kk_a", fqName: "a"),
            MetadataRecord(kind: .function, mangledName: "_kk_b", fqName: "b"),
            MetadataRecord(kind: .function, mangledName: "_kk_c", fqName: "c"),
        ]
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize(records)
        let lines = serialized.split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.first.map(String.init), "symbols=3")
        XCTAssertEqual(lines.count, 4) // header + 3 records
    }

    func testMetadataSerializeLayoutFieldsOnlyForNominalKinds() {
        // Layout fields should appear for class but NOT for function
        let classRecord = MetadataRecord(
            kind: .class,
            mangledName: "_kk_C",
            fqName: "demo.C",
            declaredFieldCount: 1,
            declaredInstanceSizeWords: 2
        )
        let funcRecord = MetadataRecord(
            kind: .function,
            mangledName: "_kk_f",
            fqName: "demo.f",
            declaredFieldCount: 1,  // should be ignored for function
            declaredInstanceSizeWords: 2  // should be ignored for function
        )
        let encoder = MetadataEncoder()

        let classStr = encoder.serialize([classRecord])
        XCTAssertTrue(classStr.contains("fields=1"))
        XCTAssertTrue(classStr.contains("layoutWords=2"))

        let funcStr = encoder.serialize([funcRecord])
        XCTAssertFalse(funcStr.contains("fields="))
        XCTAssertFalse(funcStr.contains("layoutWords="))
    }

    func testMetadataSerializeArityOnlyForFunctions() {
        // Arity should appear for function but NOT for class
        let funcRecord = MetadataRecord(
            kind: .function,
            mangledName: "_kk_f",
            fqName: "demo.f",
            arity: 3
        )
        let classRecord = MetadataRecord(
            kind: .class,
            mangledName: "_kk_C",
            fqName: "demo.C"
        )
        let encoder = MetadataEncoder()

        let funcStr = encoder.serialize([funcRecord])
        XCTAssertTrue(funcStr.contains("arity=3"))

        let classStr = encoder.serialize([classRecord])
        XCTAssertFalse(classStr.contains("arity="))
    }

    // MARK: - Integration: Sealed Class Import via Library

    func testMetadataImportRestoresSealedClassFlagViaLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtSealedClass",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        class _kk_Shape fq=ext.Shape fields=0 layoutWords=2 vtable=0 itable=0 sealedClass=1
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "SealedClassImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let shapeSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Shape" && symbol.kind == .class
            }
            XCTAssertNotNil(shapeSymbol)
            XCTAssertTrue(shapeSymbol?.flags.contains(.sealedType) ?? false)
            XCTAssertFalse(shapeSymbol?.flags.contains(.dataType) ?? true)
        }
    }

    func testMetadataImportRestoresAnnotationsViaLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtAnnotated",
          "metadata": "metadata.bin"
        }
        """
        // Build the annotations field using the same encoding the encoder uses
        let encoder = MetadataEncoder()
        let annotatedRecord = MetadataRecord(
            kind: .function,
            mangledName: "_kk_ext_old",
            fqName: "ext.oldMethod",
            arity: 0,
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["replaced"])
            ]
        )
        let serialized = encoder.serialize([annotatedRecord])
        // Extract the single line for the function
        let functionLine = serialized.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("function") }
        XCTAssertNotNil(functionLine)

        let metadata = "symbols=1\n\(functionLine!)\n"
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "AnnotatedImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ext = ctx.interner.intern("ext")
            let oldMethod = ctx.interner.intern("oldMethod")
            let symbolID = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, oldMethod]).first)
            let annotations = sema.symbols.annotations(for: symbolID)
            XCTAssertEqual(annotations.count, 1)
            XCTAssertEqual(annotations[0].annotationFQName, "kotlin.Deprecated")
            XCTAssertEqual(annotations[0].arguments, ["replaced"])
        }
    }

    // MARK: - P5-54: Missing/Invalid manifest.json

    func testMissingManifestJsonEmitsErrorAndSkipsLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        // Create metadata.bin but NO manifest.json
        let metadata = """
        symbols=1
        function _ fq=nm.foo arity=0
        """
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoManifestApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0015", in: ctx)
            let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "foo" && symbol.flags.contains(.synthetic)
            }
            XCTAssertFalse(hasImported ?? false, "Library without manifest.json should not load symbols")
        }
    }

    func testInvalidJsonManifestEmitsErrorAndSkipsLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let invalidJson = "this is not json {{{}"
        try invalidJson.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let metadata = """
        symbols=1
        function _ fq=ij.bar arity=0
        """
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "InvalidJsonApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0015", in: ctx)
            let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "bar" && symbol.flags.contains(.synthetic)
            }
            XCTAssertFalse(hasImported ?? false, "Library with invalid JSON manifest should not load symbols")
        }
    }

    // MARK: - P5-54: Missing metadata field warning

    func testManifestMissingMetadataFieldEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NoMetaField"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=nmf.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoMetaFieldApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let metadataWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0016" && $0.severity == .warning
            }
            XCTAssertFalse(metadataWarnings.isEmpty, "Should warn when 'metadata' field is missing from manifest")
        }
    }

    // MARK: - P5-54: compilerVersion validation

    func testManifestEmptyCompilerVersionEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "EmptyCV",
          "compilerVersion": "",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=ecv.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EmptyCVApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let cvWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0017" && $0.severity == .warning
            }
            XCTAssertFalse(cvWarnings.isEmpty, "Should warn when 'compilerVersion' is empty")
        }
    }

    func testManifestInvalidCompilerVersionTypeEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "BadCVType",
          "compilerVersion": 123,
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=bcvt.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadCVTypeApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let cvWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0017" && $0.severity == .warning
            }
            XCTAssertFalse(cvWarnings.isEmpty, "Should warn when 'compilerVersion' is not a string")
        }
    }

    func testManifestValidCompilerVersionDoesNotWarn() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "GoodCV",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "\(targetStr)",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=gcv.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "GoodCVApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertNoDiagnostic("KSWIFTK-LIB-0017", in: ctx)
        }
    }

    // MARK: - P5-54: Path traversal protection

    func testManifestMetadataPathTraversalEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "Traversal",
          "metadata": "../../etc/passwd"
        }
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "TraversalApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    func testManifestObjectPathTraversalEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ObjTraversal",
          "metadata": "metadata.bin",
          "objects": ["../../secret.o"]
        }
        """
        let metadata = """
        symbols=1
        function _ fq=ot.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ObjTraversalApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    func testManifestInlineKIRDirPathTraversalEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "InlineTraversal",
          "metadata": "metadata.bin",
          "inlineKIRDir": "../../../tmp"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=it.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "InlineTraversalApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    // MARK: - P5-54: Invalid objects field type

    func testManifestInvalidObjectsFieldTypeEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "BadObjects",
          "metadata": "metadata.bin",
          "objects": "not-an-array"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=bo.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadObjectsApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let objectsErrors = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0014" && $0.message.contains("Invalid 'objects' field type")
            }
            XCTAssertFalse(objectsErrors.isEmpty, "Should emit error when 'objects' is not an array")
        }
    }

    // MARK: - P5-54: Full valid manifest with all fields passes cleanly

    func testFullyValidManifestProducesNoSchemaErrors() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        let objectsDir = libDir.appendingPathComponent("objects")
        let inlineDir = libDir.appendingPathComponent("inline-kir")
        try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: inlineDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "FullValid",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "\(targetStr)",
          "objects": ["objects/FullValid_0.o"],
          "metadata": "metadata.bin",
          "inlineKIRDir": "inline-kir"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=fv.fn arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        // Create a dummy object file so path check passes
        try "".write(to: objectsDir.appendingPathComponent("FullValid_0.o"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "FullValidApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertNoDiagnostic("KSWIFTK-LIB-0010", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0011", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0012", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0013", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0014", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0015", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0016", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0017", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0018", in: ctx)

            // Verify the symbol was loaded
            let fnSymbol = ctx.sema?.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "fn" && symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(fnSymbol, "Fully valid manifest should load symbols successfully")
        }
    }

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
            isSealedClass: false, annotations: [], sealedSubclassFQNames: []
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
            isSealedClass: false, annotations: [], sealedSubclassFQNames: []
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
            isSealedClass: false, annotations: [], sealedSubclassFQNames: []
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
            isSealedClass: false, annotations: [], sealedSubclassFQNames: []
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
