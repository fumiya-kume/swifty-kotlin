#if canImport(Testing)
@testable import CompilerCore
import Testing

extension LibraryMetadataImportIntegrationTests {
    @Test
    func testLibraryImportRestoresFunctionAndPropertyTypeSignatures() throws {
        let records = [
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.id", arity: 1, typeSignature: "F1<I,I>"),
            MetadataRecord(kind: .property, mangledName: "_", fqName: "ext.answer", typeSignature: "I"),
        ]
        try withKklibFixture(moduleName: "ExtTyped", records: records) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "TypedImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let ext = ctx.interner.intern("ext")
                let idName = ctx.interner.intern("id")
                let answerName = ctx.interner.intern("answer")

                let functionSymbol = try #require(sema.symbols.lookupAll(fqName: [ext, idName]).first)
                let propertySymbol = try #require(sema.symbols.lookupAll(fqName: [ext, answerName]).first)
                let functionSignature = try #require(sema.symbols.functionSignature(for: functionSymbol))
                let propertyType = try #require(sema.symbols.propertyType(for: propertySymbol))

                #expect(functionSignature.parameterTypes.count == 1)
                #expect(functionSignature.isSuspend == false)
                #expect(sema.types.kind(of: functionSignature.parameterTypes[0]) == .primitive(.int, .nonNull))
                #expect(sema.types.kind(of: functionSignature.returnType) == .primitive(.int, .nonNull))
                #expect(sema.types.kind(of: propertyType) == .primitive(.int, .nonNull))
            }
        }
    }

    @Test
    func testLibraryImportRestoresKClassTypeSignatures() throws {
        let records = [
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.classOf", typeSignature: "F0<KC<I>>"),
            MetadataRecord(kind: .property, mangledName: "_", fqName: "ext.classRef", typeSignature: "Q<KC<I>>"),
        ]
        try withKklibFixture(moduleName: "ExtKClass", records: records) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "KClassImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let ext = ctx.interner.intern("ext")
                let classOf = ctx.interner.intern("classOf")
                let classRef = ctx.interner.intern("classRef")

                let functionSymbol = try #require(sema.symbols.lookupAll(fqName: [ext, classOf]).first)
                let propertySymbol = try #require(sema.symbols.lookupAll(fqName: [ext, classRef]).first)
                let functionSignature = try #require(sema.symbols.functionSignature(for: functionSymbol))
                let propertyType = try #require(sema.symbols.propertyType(for: propertySymbol))

                #expect(functionSignature.returnType == sema.types.makeKClassType(argument: sema.types.intType))
                #expect(propertyType == sema.types.makeKClassType(argument: sema.types.intType, nullability: .nullable))
            }
        }
    }

    @Test
    func testLibraryImportRestoresUnsignedPrimitiveTypeSignatures() throws {
        let records = [
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.uByteOrNull", typeSignature: "F0<Q<UB>>"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.uShortOrNull", typeSignature: "F0<Q<US>>"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.uIntOrNull", typeSignature: "F0<Q<UI>>"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.uLongOrNull", typeSignature: "F0<Q<UJ>>"),
        ]
        try withKklibFixture(moduleName: "ExtUnsigned", records: records) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "UnsignedImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let ext = ctx.interner.intern("ext")
                let namesAndTypes: [(String, TypeID)] = [
                    ("uByteOrNull", sema.types.makeNullable(sema.types.ubyteType)),
                    ("uShortOrNull", sema.types.makeNullable(sema.types.ushortType)),
                    ("uIntOrNull", sema.types.makeNullable(sema.types.uintType)),
                    ("uLongOrNull", sema.types.makeNullable(sema.types.ulongType)),
                ]

                for (name, expectedType) in namesAndTypes {
                    let functionName = ctx.interner.intern(name)
                    let functionSymbol = try #require(sema.symbols.lookupAll(fqName: [ext, functionName]).first)
                    let signature = try #require(sema.symbols.functionSignature(for: functionSymbol))
                    #expect(signature.returnType == expectedType)
                }
            }
        }
    }

    @Test
    func testLibraryImportRestoresExplicitNominalLayoutSlotsAndOffsets() throws {
        let records = [
            MetadataRecord(kind: .interface, mangledName: "_", fqName: "ext.Face"),
            MetadataRecord(
                kind: .class,
                mangledName: "_",
                fqName: "ext.Box",
                declaredFieldCount: 1,
                declaredInstanceSizeWords: 3,
                declaredVtableSize: 2,
                declaredItableSize: 1,
                fieldOffsets: "ext.Box.value@2",
                vtableSlots: "v2:ext.Box.get#0#0@0|property:ext.Box.value#0#0#I@1",
                itableSlots: "ext.Face@0"
            ),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.Box.get", typeSignature: "F0<I>"),
            MetadataRecord(kind: .property, mangledName: "_", fqName: "ext.Box.value", typeSignature: "I"),
        ]
        try withKklibFixture(moduleName: "ExtLayout", records: records) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "LayoutImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let ext = ctx.interner.intern("ext")
                let box = ctx.interner.intern("Box")
                let face = ctx.interner.intern("Face")
                let get = ctx.interner.intern("get")
                let value = ctx.interner.intern("value")

                let boxSymbol = try #require(sema.symbols.lookupAll(fqName: [ext, box]).first)
                let faceSymbol = try #require(sema.symbols.lookupAll(fqName: [ext, face]).first)
                let getSymbol = try #require(sema.symbols.lookupAll(fqName: [ext, box, get]).first)
                let valueSymbol = try #require(sema.symbols.lookupAll(fqName: [ext, box, value]).first)
                let layout = try #require(sema.symbols.nominalLayout(for: boxSymbol))

                #expect(layout.fieldOffsets[valueSymbol] == 2)
                #expect(layout.vtableSlots[getSymbol] == 0)
                #expect(
                    layout.vtableSlots[SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: valueSymbol)] == 1
                )
                #expect(layout.itableSlots[faceSymbol] == 0)
                #expect(layout.vtableSize == 2)
                #expect(layout.itableSize == 1)
            }
        }
    }

    @Test
    func testLibraryImportRestoresPropertyAccessorVtableSlots() throws {
        let records = [
            MetadataRecord(
                kind: .class,
                mangledName: "_",
                fqName: "ext.AbstractBox",
                declaredVtableSize: 1,
                vtableSlots: "v2:pget:ext.AbstractBox.value@0"
            ),
            MetadataRecord(
                kind: .property,
                mangledName: "_",
                fqName: "ext.AbstractBox.value",
                typeSignature: "I"
            ),
        ]
        try withKklibFixture(moduleName: "ExtPropertyLayout", records: records) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "PropertyLayoutImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let ext = ctx.interner.intern("ext")
                let abstractBox = ctx.interner.intern("AbstractBox")
                let value = ctx.interner.intern("value")
                let classSymbol = try #require(
                    sema.symbols.lookupAll(fqName: [ext, abstractBox]).first
                )
                let propertySymbol = try #require(
                    sema.symbols.lookupAll(fqName: [ext, abstractBox, value]).first
                )
                let layout = try #require(sema.symbols.nominalLayout(for: classSymbol))
                let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)

                #expect(layout.vtableSlots[getterSymbol] == 0)
                #expect(layout.vtableSize == 1)
            }
        }
    }

    @Test
    func testLibraryImportReportsMetadataInconsistencyDiagnostics() throws {
        let metadata = """
        symbols=2
        class _ fq=ext.Box schema=v1 vtable=1 vtableSlots=ext.Box.get#0#0@1,ext.Box.missing#0#0@0
        function _ fq=ext.Box.get schema=v1 arity=0 suspend=0 sig=broken
        """
        try withKklibFixture(moduleName: "ExtBroken", metadata: metadata) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "BrokenImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                assertHasDiagnostic("KSWIFTK-LIB-0003", in: ctx)
                assertHasDiagnostic("KSWIFTK-LIB-0004", in: ctx)
                assertHasDiagnostic("KSWIFTK-LIB-0005", in: ctx)
            }
        }
    }

    @Test
    func testWildcardImportResolvesKklibSymbols() throws {
        let records = [
            MetadataRecord(kind: .package, mangledName: "_", fqName: "wc.util"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "wc.util.helper", arity: 1, typeSignature: "F1<I,I>"),
            MetadataRecord(kind: .class, mangledName: "_", fqName: "wc.util.Widget"),
        ]
        try withKklibFixture(moduleName: "WildcardLib", records: records) { libDirPath in
            let source = """
            import wc.util.*
            fun main() = helper(1)
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "WildcardApp",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let helperSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "helper" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic) &&
                        symbol.fqName.map { ctx.interner.resolve($0) } == ["wc", "util", "helper"]
                }
                #expect(helperSymbol != nil, "Wildcard import should resolve library function 'helper'")

                let widgetSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "Widget" &&
                        symbol.kind == .class &&
                        symbol.flags.contains(.synthetic) &&
                        symbol.fqName.map { ctx.interner.resolve($0) } == ["wc", "util", "Widget"]
                }
                #expect(widgetSymbol != nil, "Wildcard import should resolve library class 'Widget'")
                #expect(!ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-SEMA") })
            }
        }
    }

    @Test
    func testDefaultImportResolvesKklibSymbolsFromStdlibPackages() throws {
        let records = [
            MetadataRecord(kind: .package, mangledName: "_", fqName: "kotlin"),
            MetadataRecord(kind: .package, mangledName: "_", fqName: "kotlin.collections"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "kotlin.collections.listOf", typeSignature: "F0<A>"),
        ]
        try withKklibFixture(moduleName: "StdlibStub", records: records) { libDirPath in
            let source = """
            fun main() = listOf()
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "DefaultImportApp",
                    emit: .kirDump,
                    searchPaths: [libDirPath],
                    includeStdlib: false
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let listOfSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "listOf" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic) &&
                        symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "collections", "listOf"]
                }
                #expect(listOfSymbol != nil, "Default import should resolve library function 'listOf' from kotlin.collections")
                #expect(!ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-SEMA") })
            }
        }
    }

    @Test
    func testExplicitImportStillWorksAlongsideWildcardForKklibSymbols() throws {
        let records = [
            MetadataRecord(kind: .package, mangledName: "_", fqName: "mix.api"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "mix.api.alpha"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "mix.api.beta"),
            MetadataRecord(kind: .class, mangledName: "_", fqName: "mix.api.Gamma"),
        ]
        try withKklibFixture(moduleName: "MixedLib", records: records) { libDirPath in
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
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let alphaSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "alpha" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic) &&
                        symbol.fqName.map { ctx.interner.resolve($0) } == ["mix", "api", "alpha"]
                }
                #expect(alphaSymbol != nil, "Explicit import should resolve library function 'alpha'")

                let betaSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "beta" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic) &&
                        symbol.fqName.map { ctx.interner.resolve($0) } == ["mix", "api", "beta"]
                }
                #expect(betaSymbol != nil, "Wildcard import should resolve library function 'beta'")

                let gammaSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "Gamma" &&
                        symbol.kind == .class &&
                        symbol.flags.contains(.synthetic) &&
                        symbol.fqName.map { ctx.interner.resolve($0) } == ["mix", "api", "Gamma"]
                }
                #expect(gammaSymbol != nil, "Wildcard import should resolve library class 'Gamma'")
                #expect(!ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-SEMA") })
            }
        }
    }
}
#endif
