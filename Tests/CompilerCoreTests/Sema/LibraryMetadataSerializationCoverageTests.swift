import Foundation
import XCTest
@testable import CompilerCore

final class LibraryMetadataSerializationCoverageTests: XCTestCase {
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

}
