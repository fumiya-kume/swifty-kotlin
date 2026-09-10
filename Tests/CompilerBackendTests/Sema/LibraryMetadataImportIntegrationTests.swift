#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct LibraryMetadataImportIntegrationTests {
    @Test
    func testSemaLoadsSymbolsFromKklibSearchPath() throws {
        let librarySource = """
        package extdemo
        fun plus(v: Int) = v + 1
        """
        try withCompiledLibrary(source: librarySource, moduleName: "ExtDemo") { libraryPath in
            let appSource = """
            import extdemo.plus
            fun main() = plus(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runToKIR(appCtx)

                let sema = try #require(appCtx.sema)
                let importedPlus = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic)
                }
                #expect(importedPlus != nil)
                #expect(!appCtx.diagnostics.hasError, "Unexpected errors: \(appCtx.diagnostics.diagnostics.map(\.message).joined(separator: "\n"))")
                let appFileDiagnostics = appCtx.diagnostics.diagnostics.filter { diag in
                    guard let range = diag.primaryRange else { return false }
                    return appCtx.sourceManager.path(of: range.start.file) == appPath
                }
                #expect(!appFileDiagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
            }
        }
    }

    @Test
    func testInlineLoweringExpandsImportedInlineFunctionFromKklib() throws {
        let librarySource = """
        package extdemo
        inline fun plus1(v: Int) = v + 1
        """
        try withCompiledLibrary(source: librarySource, moduleName: "ExtDemo") { libraryPath in
            let appSource = """
            import extdemo.plus1
            fun main() = plus1(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)

                let sema = try #require(appCtx.sema)
                let importedInline = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus1" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.inlineFunction)
                }
                #expect(importedInline != nil)
                #expect(!sema.importedInlineFunctions.isEmpty)

                let kir = try #require(appCtx.kir)
                let mainFunction = try #require(
                    findAllKIRFunctions(in: kir).first { function in
                        appCtx.interner.resolve(function.name) == "main"
                    },
                    "Expected lowered main function"
                )

                let calls = extractCallees(from: mainFunction.body, interner: appCtx.interner)
                #expect(!calls.contains("plus1"))
                #expect(calls.contains("kk_op_add"))
            }
        }
    }

    // KSP-472: インライン展開された本体がライブラリ側のプロパティ getter を呼ぶ場合、
    // 宣言名のままだとリンク時に undefined reference になりうる。KSP-803 以降、
    // getter は consumer の symbol table に外部リンク名付きの accessor symbol として
    // 復元されるため、KIR 上の callee 表記は宣言名のままでも良いが、その `symbol` が
    // 指すシンボルの外部リンク名は必ず mangle 済みリンク名でなければならない
    // (`symbol` が解決できない場合のみ、callee 自体が mangle 済み名にフォールバックする)。
    @Test
    func testImportedInlineBodyCallsLibraryPropertyGetterByLinkName() throws {
        let librarySource = """
        package extdemo
        val Int.doubled: Int
            get() = this * 2
        inline fun callDoubled(v: Int) = v.doubled
        """
        try withCompiledLibrary(source: librarySource, moduleName: "ExtDemo") { libraryPath in
            let appSource = """
            import extdemo.callDoubled
            fun main() = callDoubled(21)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)

                let sema = try #require(appCtx.sema)
                let kir = try #require(appCtx.kir)
                let mainFunction = try #require(
                    findAllKIRFunctions(in: kir).first { function in
                        appCtx.interner.resolve(function.name) == "main"
                    },
                    "Expected lowered main function"
                )
                let getterCall = try #require(
                    mainFunction.body.first { instruction in
                        guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                        let name = appCtx.interner.resolve(callee)
                        return name == "doubled" || name.hasPrefix("kk_fn_get_")
                    },
                    "Expected the inlined body to call the imported getter"
                )
                guard case let .call(callSymbol, callee, _, _, _, _, _, _) = getterCall else {
                    Issue.record("Expected a .call instruction")
                    return
                }
                let calleeName = appCtx.interner.resolve(callee)
                if calleeName.hasPrefix("kk_fn_get_") {
                    return
                }
                let resolvedLinkName = callSymbol.flatMap { sema.symbols.externalLinkName(for: $0) }
                #expect(
                    resolvedLinkName?.hasPrefix("kk_fn_get_") == true,
                    "Inlined body must call the getter either by its mangled link name, or through a consumer accessor symbol whose external link name is the mangled getter link; got callee=\(calleeName), resolved symbol link=\(resolvedLinkName ?? "nil")"
                )
            }
        }
    }

    @Test
    func testSemaSynthesizesNominalLayoutsAndLibraryMetadataContainsLayoutFields() throws {
        let source = """
        package layoutdemo
        class Base
        class Derived: Base
        """

        try withTemporaryFile(contents: source) { path in
            let semaCtx = makeCompilationContext(inputs: [path], moduleName: "LayoutSema", emit: .kirDump)
            try runToKIR(semaCtx)

            let sema = try #require(semaCtx.sema)
            let base = try #require(sema.symbols.allSymbols().first(where: { symbol in
                semaCtx.interner.resolve(symbol.name) == "Base" && symbol.kind == .class
            }))
            let derived = try #require(sema.symbols.allSymbols().first(where: { symbol in
                semaCtx.interner.resolve(symbol.name) == "Derived" && symbol.kind == .class
            }))

            let baseLayout = sema.symbols.nominalLayout(for: base.id)
            let derivedLayout = sema.symbols.nominalLayout(for: derived.id)
            #expect(baseLayout != nil)
            #expect(derivedLayout != nil)
            #expect(baseLayout?.objectHeaderWords == 2)
            #expect((baseLayout?.instanceSizeWords ?? 0) >= 2)
            #expect(derivedLayout?.superClass == base.id)
        }

        try withCompiledLibrary(source: source, moduleName: "LayoutLib") { libraryPath in
            let metadataText = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
            let records = MetadataDecoder().decode(metadataText)
            let derivedRecord = try #require(records.first { $0.fqName == "layoutdemo.Derived" })
            #expect(derivedRecord.declaredInstanceSizeWords != nil)
            #expect(derivedRecord.declaredVtableSize != nil)
            #expect(derivedRecord.declaredItableSize != nil)
            #expect(derivedRecord.superFQName == "layoutdemo.Base")
        }
    }

    @Test
    func testImportedEnumApisUseDeclarationOrderFromLibraryMetadata() throws {
        let librarySource = """
        package extdemo
        enum class ExternalOsFamily {
            UNKNOWN, MACOSX, IOS, LINUX, WINDOWS, ANDROID, WASM, TVOS, WATCHOS
        }
        """

        try withCompiledLibrary(source: librarySource, moduleName: "ExtEnumOrder") { libraryPath in
            let metadataText = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
            let records = MetadataDecoder().decode(metadataText)
            let enumRecord = try #require(records.first { $0.fqName == "extdemo.ExternalOsFamily" })
            #expect(enumRecord.kind == .enumClass)

            let appSource = """
            import extdemo.ExternalOsFamily

            fun main() {
                println(ExternalOsFamily.entries[7])
                println(ExternalOsFamily.valueOf("TVOS").ordinal)
            }
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "ImportedEnumOrderApp",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)

                #expect(!appCtx.diagnostics.hasError, "Unexpected errors: \(appCtx.diagnostics.diagnostics.map(\.message).joined(separator: "\n"))")

                let sema = try #require(appCtx.sema)
                let enumSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    appCtx.interner.resolve(symbol.name) == "ExternalOsFamily" && symbol.kind == .enumClass
                }))
                let nominalLayout = try #require(sema.symbols.nominalLayout(for: enumSymbol.id))

                let entrySymbols = sema.symbols.children(ofFQName: enumSymbol.fqName)
                    .compactMap { sema.symbols.symbol($0) }
                    .filter { $0.kind == .field }
                    .sorted { lhs, rhs in
                        let lhsOffset = nominalLayout.fieldOffsets[lhs.id] ?? Int.max
                        let rhsOffset = nominalLayout.fieldOffsets[rhs.id] ?? Int.max
                        if lhsOffset != rhsOffset {
                            return lhsOffset < rhsOffset
                        }
                        return lhs.id.rawValue < rhs.id.rawValue
                    }
                let orderedNames = entrySymbols.map { appCtx.interner.resolve($0.name) }
                let expectedEntryNames = [
                    "UNKNOWN", "MACOSX", "IOS", "LINUX", "WINDOWS",
                    "ANDROID", "WASM", "TVOS", "WATCHOS",
                ]
                #expect(orderedNames == expectedEntryNames)

                let kir = try #require(appCtx.kir)
                let mainFunction = try #require(
                    findAllKIRFunctions(in: kir).first { function in
                        appCtx.interner.resolve(function.name) == "main"
                    },
                    "Expected lowered main function"
                )
                let calls = extractCallees(from: mainFunction.body, interner: appCtx.interner)
                #expect(calls.contains { $0.contains("entries") })
                #expect(calls.contains { $0.contains("valueOf") })
            }
        }
    }

    @Test
    func testSemaAllocatesVtableSlotsFromImportedNominalMetadata() throws {
        let records = [
            MetadataRecord(kind: .class, mangledName: "_", fqName: "ext.C"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.C.m"),
        ]
        try withKklibFixture(moduleName: "ExtMeta", records: records) { libDirPath in
            let source = "fun main() = 0"
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "VTableImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let classSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    ctx.interner.resolve(symbol.name) == "C" && symbol.kind == .class
                }))
                let layout = sema.symbols.nominalLayout(for: classSymbol.id)
                #expect(layout != nil)
                #expect(layout?.vtableSlots.count == 1)
                #expect(layout?.vtableSize == 1)
                #expect(layout?.itableSlots.count == 0)
                #expect(layout?.itableSize == 0)
            }
        }
    }

    @Test
    func testSemaReusesVtableSlotForImportedOverrideMethods() throws {
        let records = [
            MetadataRecord(
                kind: .class,
                mangledName: "_",
                fqName: "ext.Base",
                declaredFieldCount: 0,
                declaredInstanceSizeWords: 3,
                declaredVtableSize: 1,
                declaredItableSize: 0
            ),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.Base.m"),
            MetadataRecord(
                kind: .class,
                mangledName: "_",
                fqName: "ext.Derived",
                declaredFieldCount: 0,
                declaredInstanceSizeWords: 3,
                declaredVtableSize: 1,
                declaredItableSize: 0,
                superFQName: "ext.Base"
            ),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.Derived.m"),
        ]
        try withKklibFixture(moduleName: "ExtMetaOverride", records: records) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "VTableOverrideImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let baseClass = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base")]).first)
                let derivedClass = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Derived")]).first)
                let baseMethod = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base"), ctx.interner.intern("m")]).first)
                let derivedMethod = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Derived"), ctx.interner.intern("m")]).first)

                let baseLayout = try #require(sema.symbols.nominalLayout(for: baseClass))
                let derivedLayout = try #require(sema.symbols.nominalLayout(for: derivedClass))
                #expect(derivedLayout.superClass == baseClass)
                #expect(baseLayout.vtableSize == 1)
                #expect(derivedLayout.vtableSize == 1)
                #expect(derivedLayout.vtableSlots[baseMethod] == derivedLayout.vtableSlots[derivedMethod])
            }
        }
    }

    @Test
    func testSemaInheritsImportedFieldLayoutFromMetadataHints() throws {
        let records = [
            MetadataRecord(
                kind: .class,
                mangledName: "_",
                fqName: "ext.Base",
                declaredFieldCount: 1,
                declaredInstanceSizeWords: 4,
                declaredVtableSize: 0,
                declaredItableSize: 0
            ),
        ]
        try withKklibFixture(moduleName: "ExtLayoutHint", records: records) { libDirPath in
            let source = """
            class Derived: ext.Base
            fun main() = 0
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "LayoutHintImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let baseClass = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base")]).first)
                let derivedClass = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Derived")]).first)
                let baseLayout = try #require(sema.symbols.nominalLayout(for: baseClass))
                let derivedLayout = try #require(sema.symbols.nominalLayout(for: derivedClass))

                #expect(baseLayout.instanceFieldCount == 1)
                #expect(baseLayout.instanceSizeWords == 4)
                #expect(derivedLayout.superClass == baseClass)
                #expect(derivedLayout.instanceFieldCount == 1)
                #expect(derivedLayout.instanceSizeWords == 4)
            }
        }
    }

    @Test
    func testLibraryMetadataExportsTypeSignatures() throws {
        let source = """
        package metaexport
        fun id(v: Int): Int = v
        val answer: Int = 42
        """
        try withCompiledLibrary(source: source, moduleName: "MetaExport") { libraryPath in
            let metadataText = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
            let records = MetadataDecoder().decode(metadataText)
            let idRecord = try #require(records.first { $0.fqName == "metaexport.id" })
            let answerRecord = try #require(records.first { $0.fqName == "metaexport.answer" })
            #expect(idRecord.kind == .function)
            #expect(idRecord.typeSignature == "F1<I,I>")
            #expect(answerRecord.kind == .property)
            #expect(answerRecord.typeSignature == "I")
        }
    }

    @Test
    func testImportedGenericClassResolvesExplicitTypeArgumentsAndMembers() throws {
        let source = """
        package genericlib
        class Holder<T> {
            fun wrap(value: T): T = value
        }
        """
        try withCompiledLibrary(source: source, moduleName: "GenericLib") { libraryPath in
            let metadataText = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
            let records = MetadataDecoder().decode(metadataText)
            let holderRecord = try #require(records.first { $0.fqName == "genericlib.Holder" })
            #expect(holderRecord.nominalTypeParameters != nil)

            let appSource = """
            import genericlib.Holder
            fun main() {
                val holder = Holder<Int>()
                println(holder.wrap(1))
            }
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "GenericApp",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runToKIR(appCtx)

                #expect(
                    !appCtx.diagnostics.hasError,
                    "Unexpected errors: \(appCtx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.message).joined(separator: "\n"))"
                )

                let sema = try #require(appCtx.sema)
                let holder = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    appCtx.interner.resolve(symbol.name) == "Holder" && symbol.kind == .class
                }))
                #expect(sema.types.nominalTypeParameterSymbols(for: holder.id).count == 1)
            }
        }
    }

    @Test
    func testLibraryMetadataRoundTripsContextFunctionTypeSignatures() throws {
        let source = """
        package metaexport
        class A
        class B
        class C
        class D
        typealias Handler = context(A, B) C.() -> D
        val handler: Handler? = null
        """
        try withCompiledLibrary(source: source, moduleName: "MetaExportContext") { libraryPath in
            let metadataText = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
            let records = MetadataDecoder().decode(metadataText)
            let handlerTypeAlias = try #require(records.first { $0.fqName == "metaexport.Handler" })
            let handlerProperty = try #require(records.first { $0.fqName == "metaexport.handler" })
            #expect(handlerTypeAlias.kind == .typeAlias)
            #expect(handlerProperty.typeSignature == "Q<Lmetaexport.Handler;>")

            let appSource = """
            import metaexport.handler
            fun use(): Any? = handler
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let importCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "MetaExportContextImport",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runSema(importCtx)

                let sema = try #require(importCtx.sema)
                let handlerProperty = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    importCtx.interner.resolve(symbol.name) == "handler" &&
                        symbol.kind == .property &&
                        symbol.flags.contains(.synthetic)
                }))
                let propertyType = try #require(sema.symbols.propertyType(for: handlerProperty.id))
                let nonNullPropertyType = sema.types.makeNonNullable(propertyType)
                switch sema.types.kind(of: nonNullPropertyType) {
                case .any(.nonNull):
                    #expect(sema.types.renderType(nonNullPropertyType).contains("Any"))
                case let .functionType(functionType):
                    #expect(functionType.contextReceivers.count == 2)
                    #expect(functionType.receiver != nil)
                default:
                    Issue.record("Expected imported handler to be Any or a context-receiver function type, got \(sema.types.renderType(nonNullPropertyType))")
                }
            }
        }
    }

    @Test
    func testPlatformWarningEmittedForImportedMissingSignatureInExplicitNonNullContext() throws {
        let records = [
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.platformValue"),
        ]
        try withKklibFixture(moduleName: "ExtPlatformWarn", records: records) { libDirPath in
            let source = """
            import ext.platformValue

            fun useExplicit(): Any {
                val x: Any = platformValue()
                return x
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "PlatformWarn",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)

                let warnings = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-PLATFORM" }
                #expect(
                    !warnings.isEmpty,
                    "Expected KSWIFTK-SEMA-PLATFORM, got: \(ctx.diagnostics.diagnostics.map(\.code))"
                )
                #expect(warnings.allSatisfy { $0.primaryRange != nil })
            }
        }
    }

    @Test
    func testPlatformWarningSuppressedForInferredReturnTypeFromImportedMissingSignature() throws {
        let records = [
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.platformValue"),
        ]
        try withKklibFixture(moduleName: "ExtPlatformSuppressed", records: records) { libDirPath in
            let source = """
            import ext.platformValue

            fun inferred() = platformValue()
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "PlatformWarnSuppressed",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-PLATFORM", in: ctx)
            }
        }
    }

    @Test
    func testPlatformValueAssignsToExplicitNullableContextWithoutWarning() throws {
        let records = [
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.platformValue"),
        ]
        try withKklibFixture(moduleName: "ExtPlatformNullable", records: records) { libDirPath in
            let source = """
            import ext.platformValue

            fun useNullable(): Any? {
                val x: Any? = platformValue()
                return x
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "PlatformNullable",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-PLATFORM", in: ctx)
                #expect(!ctx.diagnostics.hasError)
            }
        }
    }

    /// Regression: when metadata provides Collection.contains, listOf(...).contains must not emit VAR-OUT.
    /// Verifies metadata import and synthetic stub interaction for variance relaxation.
    @Test
    func testMetadataCollectionContainsDoesNotCauseVarOutWithListOf() throws {
        let records = [
            MetadataRecord(kind: .interface, mangledName: "_", fqName: "kotlin.collections.Collection"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "kotlin.collections.Collection.contains", arity: 1),
        ]
        try withKklibFixture(moduleName: "ExtCollectionMeta", records: records) { libDirPath in
            let source = """
            fun main() {
                val list = listOf(1, 2, 3)
                list.contains(2)
                list.isEmpty()
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "CollectionMetaApp",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
                #expect(!ctx.diagnostics.hasError)
            }
        }
    }
}
#endif
