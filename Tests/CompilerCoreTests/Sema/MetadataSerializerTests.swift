@testable import CompilerCore
import XCTest

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
                let key = String(token[token.startIndex ..< eqIdx])
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
            MetadataRecord(kind: .class, mangledName: "m2", fqName: "test.Cls")
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
        let content = "symbols=1\nfunction _KK_test__fn__F__sig fq=test.fn schema=v1 arity=2 suspend=0 inline=0 sig=F2<I,I,I>\n"
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
        let content = "symbols=1\nfunction _KK fq=test.fn schema=v1 arity=1 suspend=1 inline=1 sig=SF1<I,U>\n"
        let records = decoder.decode(content)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isSuspend)
        XCTAssertTrue(records[0].isInline)
    }

    func testDecodeClassWithLayout() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Foo schema=v1 layoutWords=5 fields=3 vtable=2 itable=1 superFq=test.Base fieldOffsets=x@0 vtableSlots=bar@0 itableSlots=baz@0\n"
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
}
