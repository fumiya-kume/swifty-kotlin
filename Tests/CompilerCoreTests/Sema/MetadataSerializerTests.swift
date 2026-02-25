import XCTest
@testable import CompilerCore

final class MetadataSerializerTests: XCTestCase {

    // MARK: - Helpers

    /// Parse the serialized record line (after the header) into space-separated tokens,
    /// then extract key=value pairs for precise field assertions.
    private func parseRecordLine(_ output: String) -> (kind: String, mangledName: String, fields: [String: String]) {
        // The serialized format is: "symbols=N\nkind mangledName key=val key=val...\n"
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 2 else { return ("", "", [:]) }
        let recordLine = String(lines[1])
        let tokens = recordLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 2 else { return ("", "", [:]) }
        let kind = tokens[0]
        let mangledName = tokens[1]
        var fields: [String: String] = [:]
        for token in tokens.dropFirst(2) {
            if let eqIdx = token.firstIndex(of: "=") {
                let key = String(token[token.startIndex..<eqIdx])
                let value = String(token[token.index(after: eqIdx)...])
                fields[key] = value
            }
        }
        return (kind, mangledName, fields)
    }

    // MARK: - MetadataRecord init

    func testMetadataRecordDefaults() {
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
        XCTAssertFalse(record.isValueClass)
        XCTAssertNil(record.valueClassUnderlyingTypeSig)
        XCTAssertTrue(record.sealedSubclassFQNames.isEmpty)
        XCTAssertTrue(record.annotations.isEmpty)
    }

    func testMetadataRecordWithAllFields() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_mod__Foo__C__abc",
            fqName: "com.example.Foo",
            arity: 2,
            isSuspend: true,
            isInline: true,
            typeSignature: "sig",
            externalLinkName: "link",
            declaredFieldCount: 3,
            declaredInstanceSizeWords: 4,
            declaredVtableSize: 5,
            declaredItableSize: 6,
            superFQName: "com.example.Base",
            fieldOffsets: "f1@0,f2@1",
            vtableSlots: "m1@0",
            itableSlots: "i1@0",
            isDataClass: true,
            isSealedClass: true,
            annotations: [MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated")],
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I",
            sealedSubclassFQNames: ["com.example.SubA", "com.example.SubB"]
        )
        XCTAssertEqual(record.kind, .class)
        XCTAssertEqual(record.mangledName, "_KK_mod__Foo__C__abc")
        XCTAssertEqual(record.fqName, "com.example.Foo")
        XCTAssertEqual(record.arity, 2)
        XCTAssertTrue(record.isSuspend)
        XCTAssertTrue(record.isInline)
        XCTAssertEqual(record.typeSignature, "sig")
        XCTAssertEqual(record.externalLinkName, "link")
        XCTAssertEqual(record.declaredFieldCount, 3)
        XCTAssertEqual(record.declaredInstanceSizeWords, 4)
        XCTAssertEqual(record.declaredVtableSize, 5)
        XCTAssertEqual(record.declaredItableSize, 6)
        XCTAssertEqual(record.superFQName, "com.example.Base")
        XCTAssertTrue(record.isDataClass)
        XCTAssertTrue(record.isSealedClass)
        XCTAssertTrue(record.isValueClass)
        XCTAssertEqual(record.valueClassUnderlyingTypeSig, "I")
        XCTAssertEqual(record.sealedSubclassFQNames, ["com.example.SubA", "com.example.SubB"])
        XCTAssertEqual(record.annotations.count, 1)
    }

    // MARK: - MetadataAnnotationRecord

    func testAnnotationRecordDefaults() {
        let ann = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated")
        XCTAssertEqual(ann.annotationFQName, "kotlin.Deprecated")
        XCTAssertTrue(ann.arguments.isEmpty)
        XCTAssertNil(ann.useSiteTarget)
    }

    func testAnnotationRecordWithAllFields() {
        let ann = MetadataAnnotationRecord(
            annotationFQName: "kotlin.Deprecated",
            arguments: ["Use newMethod instead", "WARNING"],
            useSiteTarget: "get"
        )
        XCTAssertEqual(ann.annotationFQName, "kotlin.Deprecated")
        XCTAssertEqual(ann.arguments, ["Use newMethod instead", "WARNING"])
        XCTAssertEqual(ann.useSiteTarget, "get")
    }

    func testAnnotationRecordEquatable() {
        let ann1 = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated")
        let ann2 = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated")
        let ann3 = MetadataAnnotationRecord(annotationFQName: "kotlin.JvmStatic")
        XCTAssertEqual(ann1, ann2)
        XCTAssertNotEqual(ann1, ann3)
    }

    // MARK: - MetadataEncoder serialize

    func testSerializeFunctionRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__add__F__sig",
            fqName: "test.add",
            arity: 2,
            isSuspend: false,
            isInline: false,
            typeSignature: "F2<I,I,I>"
        )
        let output = encoder.serialize([record])
        XCTAssertTrue(output.hasPrefix("symbols=1\n"))
        let parsed = parseRecordLine(output)
        XCTAssertEqual(parsed.kind, "function")
        XCTAssertEqual(parsed.fields["fq"], "test.add")
        XCTAssertEqual(parsed.fields["arity"], "2")
        XCTAssertEqual(parsed.fields["suspend"], "0")
        XCTAssertEqual(parsed.fields["inline"], "0")
        XCTAssertEqual(parsed.fields["sig"], "F2<I,I,I>")
    }

    func testSerializeSuspendFunction() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__fetch__F__sig",
            fqName: "test.fetch",
            arity: 1,
            isSuspend: true,
            isInline: true,
            typeSignature: "SF1<I,U>"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        XCTAssertEqual(parsed.fields["suspend"], "1")
        XCTAssertEqual(parsed.fields["inline"], "1")
    }

    func testSerializeClassWithLayout() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Foo__C__",
            fqName: "test.Foo",
            declaredFieldCount: 3,
            declaredInstanceSizeWords: 5,
            declaredVtableSize: 2,
            declaredItableSize: 1,
            superFQName: "test.Base",
            fieldOffsets: "test.Foo.x@0,test.Foo.y@1",
            vtableSlots: "test.Foo.bar#0#0@0",
            itableSlots: "test.IFoo.baz@0"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        XCTAssertEqual(parsed.kind, "class")
        XCTAssertEqual(parsed.fields["layoutWords"], "5")
        XCTAssertEqual(parsed.fields["fields"], "3")
        XCTAssertEqual(parsed.fields["vtable"], "2")
        XCTAssertEqual(parsed.fields["itable"], "1")
        XCTAssertEqual(parsed.fields["superFq"], "test.Base")
        XCTAssertEqual(parsed.fields["fieldOffsets"], "test.Foo.x@0,test.Foo.y@1")
        XCTAssertEqual(parsed.fields["vtableSlots"], "test.Foo.bar#0#0@0")
        XCTAssertEqual(parsed.fields["itableSlots"], "test.IFoo.baz@0")
    }

    func testSerializeDataClassFlag() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Data__C__",
            fqName: "test.Data",
            isDataClass: true
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        XCTAssertEqual(parsed.fields["dataClass"], "1")
    }

    func testSerializeSealedClassFlag() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Sealed__C__",
            fqName: "test.Sealed",
            isSealedClass: true,
            sealedSubclassFQNames: ["test.SubA", "test.SubB"]
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        XCTAssertEqual(parsed.fields["sealedClass"], "1")
        XCTAssertEqual(parsed.fields["sealedSubs"], "test.SubA,test.SubB")
    }

    func testSerializeValueClassFlag() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Wrapper__C__",
            fqName: "test.Wrapper",
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        XCTAssertEqual(parsed.fields["valueClass"], "1")
        XCTAssertEqual(parsed.fields["valueUnderlying"], "I")
    }

    func testSerializePropertyWithSignature() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .property,
            mangledName: "_KK_test__x__P__I",
            fqName: "test.x",
            typeSignature: "I"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        XCTAssertEqual(parsed.kind, "property")
        XCTAssertEqual(parsed.fields["sig"], "I")
    }

    func testSerializeTypeAliasWithSignature() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .typeAlias,
            mangledName: "_KK_test__MyInt__T__I",
            fqName: "test.MyInt",
            typeSignature: "I"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        XCTAssertEqual(parsed.kind, "typeAlias")
        XCTAssertEqual(parsed.fields["sig"], "I")
    }

    func testSerializeConstructorRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .constructor,
            mangledName: "_KK_test__Foo__init__K__sig",
            fqName: "test.Foo.init",
            arity: 1,
            typeSignature: "F1<I,U>",
            externalLinkName: "Foo_init"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        XCTAssertEqual(parsed.kind, "constructor")
        XCTAssertEqual(parsed.fields["arity"], "1")
        XCTAssertEqual(parsed.fields["link"], "Foo_init")
    }

    func testSerializeAnnotations() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__fn__F__sig",
            fqName: "test.fn",
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["old"],
                    useSiteTarget: "get"
                )
            ]
        )
        let output = encoder.serialize([record])
        XCTAssertTrue(output.contains("annotations="))
        XCTAssertTrue(output.contains("kotlin.Deprecated"))
        XCTAssertTrue(output.contains("target:get"))
    }

    func testSerializeMultipleRecords() {
        let encoder = MetadataEncoder()
        let records = [
            MetadataRecord(kind: .function, mangledName: "m1", fqName: "test.fn1"),
            MetadataRecord(kind: .class, mangledName: "m2", fqName: "test.Cls"),
        ]
        let output = encoder.serialize(records)
        XCTAssertTrue(output.hasPrefix("symbols=2\n"))
        XCTAssertTrue(output.contains("function"))
        XCTAssertTrue(output.contains("class"))
    }

    func testSerializeEmptyRecords() {
        let encoder = MetadataEncoder()
        let output = encoder.serialize([])
        XCTAssertEqual(output, "symbols=0\n")
    }

    // MARK: - MetadataDecoder

    func testDecodeFunctionRecord() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nfunction _KK_test__fn__F__sig fq=test.fn arity=2 suspend=0 inline=0 sig=F2<I,I,I>\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .function)
        XCTAssertEqual(records[0].fqName, "test.fn")
        XCTAssertEqual(records[0].arity, 2)
        XCTAssertFalse(records[0].isSuspend)
        XCTAssertFalse(records[0].isInline)
        XCTAssertEqual(records[0].typeSignature, "F2<I,I,I>")
    }

    func testDecodeSuspendFunction() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nfunction _KK fq=test.fn arity=1 suspend=1 inline=1 sig=SF1<I,U>\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isSuspend)
        XCTAssertTrue(records[0].isInline)
    }

    func testDecodeClassWithLayout() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Foo layoutWords=5 fields=3 vtable=2 itable=1 superFq=test.Base fieldOffsets=x@0 vtableSlots=bar@0 itableSlots=baz@0\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .class)
        XCTAssertEqual(records[0].declaredInstanceSizeWords, 5)
        XCTAssertEqual(records[0].declaredFieldCount, 3)
        XCTAssertEqual(records[0].declaredVtableSize, 2)
        XCTAssertEqual(records[0].declaredItableSize, 1)
        XCTAssertEqual(records[0].superFQName, "test.Base")
        XCTAssertEqual(records[0].fieldOffsets, "x@0")
        XCTAssertEqual(records[0].vtableSlots, "bar@0")
        XCTAssertEqual(records[0].itableSlots, "baz@0")
    }

    func testDecodeDataClassFlag() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Data dataClass=1\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isDataClass)
    }

    func testDecodeSealedClassWithSubs() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Sealed sealedClass=1 sealedSubs=test.SubA,test.SubB\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isSealedClass)
        XCTAssertEqual(records[0].sealedSubclassFQNames, ["test.SubA", "test.SubB"])
    }

    func testDecodeValueClass() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Wrapper valueClass=1 valueUnderlying=I\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isValueClass)
        XCTAssertEqual(records[0].valueClassUnderlyingTypeSig, "I")
    }

    func testDecodeConstructorWithLink() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nconstructor _KK fq=test.Foo.init arity=1 suspend=0 inline=0 sig=F1<I,U> link=Foo_init\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .constructor)
        XCTAssertEqual(records[0].externalLinkName, "Foo_init")
    }

    func testDecodePropertyWithSig() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nproperty _KK fq=test.x sig=I\n"
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
        let content = "symbols=1\nunknownKind _KK fq=test.fn\n"
        let records = decoder.decode(content)
        XCTAssertTrue(records.isEmpty)
    }

    func testDecodeMultipleRecords() {
        let decoder = MetadataDecoder()
        let content = """
        symbols=2
        function _KK1 fq=test.fn1 arity=0 suspend=0 inline=0
        class _KK2 fq=test.Cls
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
        let content = "symbols=1\nfield _KK fq=test.Foo.x sig=I\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .field)
    }

    func testDecodeTypeAliasRecord() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\ntypeAlias _KK fq=test.MyInt sig=I\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .typeAlias)
        XCTAssertEqual(records[0].typeSignature, "I")
    }
}
