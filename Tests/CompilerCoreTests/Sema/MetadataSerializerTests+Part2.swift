import XCTest
@testable import CompilerCore


extension MetadataSerializerTests {
    func testDecodeDataClassFlag() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Data schema=v1 dataClass=1\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isDataClass)
    }

    func testDecodeSealedClassWithSubs() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Sealed schema=v1 sealedClass=1 sealedSubs=test.SubA,test.SubB\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isSealedClass)
        XCTAssertEqual(records[0].sealedSubclassFQNames, ["test.SubA", "test.SubB"])
    }

    func testDecodeValueClass() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Wrapper schema=v1 valueClass=1 valueUnderlying=I\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isValueClass)
        XCTAssertEqual(records[0].valueClassUnderlyingTypeSig, "I")
    }

    func testDecodeConstructorWithLink() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nconstructor _KK fq=test.Foo.init schema=v1 arity=1 suspend=0 inline=0 sig=F1<I,U> link=Foo_init\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .constructor)
        XCTAssertEqual(records[0].externalLinkName, "Foo_init")
    }

    func testDecodePropertyWithSig() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nproperty _KK fq=test.x schema=v1 sig=I\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .property)
        XCTAssertEqual(records[0].typeSignature, "I")
    }

    func testDecodeEmptyContent() {
        let decoder = MetadataDecoder()
        let records = decoder.decode("")
        XCTAssertTrue(records.isEmpty)
    }

    func testDecodeOnlySymbolsHeader() {
        let decoder = MetadataDecoder()
        let records = decoder.decode("symbols=0\n")
        XCTAssertTrue(records.isEmpty)
    }

    func testDecodeSkipsLinesWithoutFQ() {
        let decoder = MetadataDecoder()
        // A line without fq= should be skipped
        let content = "symbols=1\nfunction _KK arity=2\n"
        let records = decoder.decode(content)
        XCTAssertTrue(records.isEmpty)
    }

    func testDecodeSkipsUnknownKind() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nunknownKind _KK fq=test.fn schema=v1\n"
        let records = decoder.decode(content)
        XCTAssertTrue(records.isEmpty)
    }

    func testDecodeMultipleRecords() {
        let decoder = MetadataDecoder()
        let content = """
        symbols=2
        function _KK1 fq=test.fn1 schema=v1 arity=0 suspend=0 inline=0
        class _KK2 fq=test.Cls schema=v1
        """
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].kind, .function)
        XCTAssertEqual(records[1].kind, .class)
    }

    // MARK: - Encode/Decode round-trip

    func testSerializeDeserializeRoundTripFunction() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let original = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__add__F__sig",
            fqName: "test.add",
            arity: 2,
            isSuspend: true,
            isInline: true,
            typeSignature: "F2<I,I,I>"
        )
        let serialized = encoder.serialize([original])
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, original.kind)
        XCTAssertEqual(decoded[0].fqName, original.fqName)
        XCTAssertEqual(decoded[0].arity, original.arity)
        XCTAssertEqual(decoded[0].isSuspend, original.isSuspend)
        XCTAssertEqual(decoded[0].isInline, original.isInline)
        XCTAssertEqual(decoded[0].typeSignature, original.typeSignature)
    }

    func testSerializeDeserializeRoundTripClassWithLayout() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let original = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Foo__C__",
            fqName: "test.Foo",
            declaredFieldCount: 2,
            declaredInstanceSizeWords: 4,
            declaredVtableSize: 3,
            declaredItableSize: 1,
            superFQName: "test.Base",
            isDataClass: true,
            isSealedClass: true,
            sealedSubclassFQNames: ["test.SubA"]
        )
        let serialized = encoder.serialize([original])
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .class)
        XCTAssertEqual(decoded[0].fqName, "test.Foo")
        XCTAssertEqual(decoded[0].declaredFieldCount, 2)
        XCTAssertEqual(decoded[0].declaredInstanceSizeWords, 4)
        XCTAssertEqual(decoded[0].declaredVtableSize, 3)
        XCTAssertEqual(decoded[0].declaredItableSize, 1)
        XCTAssertEqual(decoded[0].superFQName, "test.Base")
        XCTAssertTrue(decoded[0].isDataClass)
        XCTAssertTrue(decoded[0].isSealedClass)
        XCTAssertEqual(decoded[0].sealedSubclassFQNames, ["test.SubA"])
    }

    func testSerializeDeserializeRoundTripValueClass() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let original = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__W__C__",
            fqName: "test.W",
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I"
        )
        let serialized = encoder.serialize([original])
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertTrue(decoded[0].isValueClass)
        XCTAssertEqual(decoded[0].valueClassUnderlyingTypeSig, "I")
    }

    func testSerializeDeserializeRoundTripAnnotations() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let original = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__fn__F__",
            fqName: "test.fn",
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["Use newFn"],
                    useSiteTarget: "get"
                ),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.JvmStatic"
                )
            ]
        )
        let serialized = encoder.serialize([original])
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].annotations.count, 2)
        XCTAssertEqual(decoded[0].annotations[0].annotationFQName, "kotlin.Deprecated")
        XCTAssertEqual(decoded[0].annotations[0].arguments, ["Use newFn"])
        XCTAssertEqual(decoded[0].annotations[0].useSiteTarget, "get")
        XCTAssertEqual(decoded[0].annotations[1].annotationFQName, "kotlin.JvmStatic")
    }

    func testSerializeDeserializeRoundTripMultipleRecords() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let records = [
            MetadataRecord(kind: .function, mangledName: "m1", fqName: "test.fn1", arity: 0),
            MetadataRecord(kind: .class, mangledName: "m2", fqName: "test.Cls"),
            MetadataRecord(kind: .interface, mangledName: "m3", fqName: "test.IFace"),
            MetadataRecord(kind: .property, mangledName: "m4", fqName: "test.prop", typeSignature: "I"),
            MetadataRecord(kind: .object, mangledName: "m5", fqName: "test.Obj"),
        ]
        let serialized = encoder.serialize(records)
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded.count, 5)
        XCTAssertEqual(decoded[0].kind, .function)
        XCTAssertEqual(decoded[1].kind, .class)
        XCTAssertEqual(decoded[2].kind, .interface)
        XCTAssertEqual(decoded[3].kind, .property)
        XCTAssertEqual(decoded[4].kind, .object)
    }

    // MARK: - symbolKindFromMetadata

    func testSymbolKindFromMetadataAllKinds() {
        let decoder = MetadataDecoder()
        let mapping: [(String, SymbolKind)] = [
            ("package", .package),
            ("class", .class),
            ("interface", .interface),
            ("object", .object),
            ("enumClass", .enumClass),
            ("annotationClass", .annotationClass),
            ("typeAlias", .typeAlias),
            ("function", .function),
            ("constructor", .constructor),
            ("property", .property),
            ("field", .field),
            ("typeParameter", .typeParameter),
            ("valueParameter", .valueParameter),
            ("local", .local),
            ("label", .label),
        ]
        for (token, expectedKind) in mapping {
            let result = decoder.symbolKindFromMetadata(token)
            XCTAssertEqual(result, expectedKind, "Expected \(expectedKind) for token '\(token)'")
        }
    }

    func testSymbolKindFromMetadataReturnsNilForUnknown() {
        let decoder = MetadataDecoder()
        XCTAssertNil(decoder.symbolKindFromMetadata("unknownType"))
        XCTAssertNil(decoder.symbolKindFromMetadata(""))
        XCTAssertNil(decoder.symbolKindFromMetadata("CLASS"))
    }

    // MARK: - MetadataEncoder annotation encoding edge cases

    func testSerializeAnnotationWithEmptyArguments() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK",
            fqName: "test.fn",
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.JvmStatic")
            ]
        )
        let output = encoder.serialize([record])
        XCTAssertTrue(output.contains("annotations=kotlin.JvmStatic"))
    }

    func testSerializeAnnotationWithUseSiteTargetAndArgs() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK",
            fqName: "test.fn",
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["msg1", "msg2"],
                    useSiteTarget: "set"
                )
            ]
        )
        let serialized = encoder.serialize([record])
        let decoded = decoder.decode(serialized)
        XCTAssertEqual(decoded[0].annotations.count, 1)
        XCTAssertEqual(decoded[0].annotations[0].annotationFQName, "kotlin.Deprecated")
        XCTAssertEqual(decoded[0].annotations[0].arguments, ["msg1", "msg2"])
        XCTAssertEqual(decoded[0].annotations[0].useSiteTarget, "set")
    }

    // MARK: - Nominal kinds coverage

    func testSerializeInterfaceRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .interface,
            mangledName: "_KK_test__IFoo__I__",
            fqName: "test.IFoo",
            declaredVtableSize: 1
        )
        let output = encoder.serialize([record])
        XCTAssertTrue(output.contains("interface"))
        XCTAssertTrue(output.contains("vtable=1"))
    }

    func testSerializeObjectRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .object,
            mangledName: "_KK_test__Companion__O__",
            fqName: "test.Companion",
            declaredInstanceSizeWords: 1
        )
        let output = encoder.serialize([record])
        XCTAssertTrue(output.contains("object"))
        XCTAssertTrue(output.contains("layoutWords=1"))
    }

    func testSerializeEnumClassRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .enumClass,
            mangledName: "_KK_test__Color__E__",
            fqName: "test.Color",
            declaredFieldCount: 3
        )
        let output = encoder.serialize([record])
        XCTAssertTrue(output.contains("enumClass"))
        XCTAssertTrue(output.contains("fields=3"))
    }

    func testSerializeAnnotationClassRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .annotationClass,
            mangledName: "_KK_test__MyAnno__A__",
            fqName: "test.MyAnno"
        )
        let output = encoder.serialize([record])
        XCTAssertTrue(output.contains("annotationClass"))
    }

    func testDecodeFieldRecord() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nfield _KK fq=test.Foo.x schema=v1 sig=I\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .field)
    }

    func testDecodeTypeAliasRecord() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\ntypeAlias _KK fq=test.MyInt schema=v1 sig=I\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .typeAlias)
        XCTAssertEqual(records[0].typeSignature, "I")
    }
}
