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
}
