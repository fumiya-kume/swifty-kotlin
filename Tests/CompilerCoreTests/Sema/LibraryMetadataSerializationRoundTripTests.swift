@testable import CompilerCore
import Foundation
import XCTest

final class LibraryMetadataSerializationRoundTripTests: XCTestCase {
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
            )
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

    func testMetadataDecoderRejectsRecordsWithoutSchema() {
        let legacy = """
        symbols=1
        class _kk_ext_C fq=ext.C fields=0 layoutWords=3 vtable=0 itable=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(legacy)
        XCTAssertEqual(decoded.count, 0)
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
            )
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
        class _kk_Point fq=ext.Point schema=v1 fields=2 layoutWords=4 vtable=0 itable=0 dataClass=1
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
        XCTAssertEqual(decoder.symbolKindFromMetadata("backingField"), .backingField)
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
        unknownKind _kk_foo fq=demo.Foo schema=v1
        function _kk_bar fq=demo.bar schema=v1 arity=0 suspend=0 inline=0
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
        function _kk_bar fq=demo.bar schema=v1 randomtoken arity=2 suspend=1 inline=0
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
        class _kk_Foo fq=demo.Foo schema=v1 futureKey=futureValue fields=1 layoutWords=2
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
}
