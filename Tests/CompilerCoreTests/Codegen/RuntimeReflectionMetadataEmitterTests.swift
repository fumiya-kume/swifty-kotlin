@testable import CompilerCore
import XCTest

final class RuntimeReflectionMetadataEmitterTests: XCTestCase {
    // MARK: - Binary Format Header

    func testSerializeEmptyRecordsProducesValidHeader() {
        let data = RuntimeReflectionMetadataEmitter.serialize([])
        // Header: magic(4) + version(4) + count(4) + strTableOffset(4) = 16
        // String table: entryCount(4) = 4
        XCTAssertEqual(data.count, 20)

        let decoded = RuntimeReflectionMetadataDecoder.decode(data)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 0)
    }

    func testSerializeMagicAndVersion() {
        let data = RuntimeReflectionMetadataEmitter.serialize([])
        // Read magic bytes (little-endian serialized as 0x4D524B4B).
        let magic = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: magic), RuntimeReflectionMetadataEmitter.magic)

        // Read version
        let version = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: version), 1)
    }

    // MARK: - Single Record Round-Trip

    func testSerializeAndDecodeSingleClassRecord() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Foo__C__",
            fqName: "test.Foo",
            declaredFieldCount: 3,
            declaredInstanceSizeWords: 5,
            superFQName: "test.Base",
            isDataClass: true
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 1)

        let r = decoded![0]
        XCTAssertEqual(r.kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.class))
        XCTAssertEqual(r.fqName, "test.Foo")
        XCTAssertEqual(r.simpleName, "Foo")
        XCTAssertEqual(r.superFqName, "test.Base")
        XCTAssertEqual(r.fieldCount, 3)
        XCTAssertEqual(r.instanceSizeWords, 5)

        // Flags: dataClass = bit 0
        XCTAssertEqual(r.flags & 0x01, 1)
    }

    func testSerializeAndDecodeSingleFunctionRecord() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__add__F__sig",
            fqName: "test.add",
            arity: 2,
            isSuspend: true,
            isInline: true,
            typeSignature: "F2<I,I,I>"
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 1)

        let r = decoded![0]
        XCTAssertEqual(r.kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.function))
        XCTAssertEqual(r.fqName, "test.add")
        XCTAssertEqual(r.simpleName, "add")
        XCTAssertEqual(r.arity, 2)
        XCTAssertNil(r.superFqName)
        XCTAssertNil(r.fieldCount)
        XCTAssertNil(r.instanceSizeWords)

        // Flags: suspend = bit 3, inline = bit 4
        XCTAssertEqual(r.flags & (1 << 3), 1 << 3, "suspend flag should be set")
        XCTAssertEqual(r.flags & (1 << 4), 1 << 4, "inline flag should be set")
    }

    // MARK: - Multiple Records

    func testSerializeAndDecodeMultipleRecords() {
        let records = [
            MetadataRecord(kind: .class, mangledName: "m1", fqName: "pkg.ClassA", declaredFieldCount: 2),
            MetadataRecord(kind: .interface, mangledName: "m2", fqName: "pkg.IFace"),
            MetadataRecord(kind: .object, mangledName: "m3", fqName: "pkg.Companion"),
            MetadataRecord(kind: .function, mangledName: "m4", fqName: "pkg.greet", arity: 1),
        ]
        let data = RuntimeReflectionMetadataEmitter.serialize(records)
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 4)

        XCTAssertEqual(decoded?[0].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.class))
        XCTAssertEqual(decoded?[0].fqName, "pkg.ClassA")
        XCTAssertEqual(decoded?[0].fieldCount, 2)

        XCTAssertEqual(decoded?[1].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.interface))
        XCTAssertEqual(decoded?[1].fqName, "pkg.IFace")

        XCTAssertEqual(decoded?[2].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.object))
        XCTAssertEqual(decoded?[2].fqName, "pkg.Companion")

        XCTAssertEqual(decoded?[3].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.function))
        XCTAssertEqual(decoded?[3].fqName, "pkg.greet")
        XCTAssertEqual(decoded?[3].arity, 1)
    }

    // MARK: - Flags Encoding

    func testFlagsBitEncoding() {
        // dataClass=1, sealedClass=1, valueClass=1, suspend=1, inline=1
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK",
            fqName: "test.AllFlags",
            isSuspend: true,
            isInline: true,
            isDataClass: true,
            isSealedClass: true,
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I"
        )
        let flags = RuntimeReflectionMetadataEmitter.encodeFlags(record)
        XCTAssertEqual(flags & (1 << 0), 1 << 0, "dataClass bit")
        XCTAssertEqual(flags & (1 << 1), 1 << 1, "sealedClass bit")
        XCTAssertEqual(flags & (1 << 2), 1 << 2, "valueClass bit")
        XCTAssertEqual(flags & (1 << 3), 1 << 3, "suspend bit")
        XCTAssertEqual(flags & (1 << 4), 1 << 4, "inline bit")
    }

    func testFlagsAllZero() {
        let record = MetadataRecord(kind: .class, mangledName: "_KK", fqName: "test.Plain")
        let flags = RuntimeReflectionMetadataEmitter.encodeFlags(record)
        XCTAssertEqual(flags, 0)
    }

    // MARK: - Kind Ordinal Coverage

    func testKindOrdinalForAllKinds() {
        // Verify unique ordinals for all kinds.
        let allKinds: [SymbolKind] = [
            .package, .class, .interface, .object, .enumClass,
            .annotationClass, .typeAlias, .function, .constructor,
            .property, .field, .backingField, .typeParameter,
            .valueParameter, .local, .label,
        ]
        var ordinals = Set<UInt8>()
        for kind in allKinds {
            let ordinal = RuntimeReflectionMetadataEmitter.kindOrdinal(kind)
            XCTAssertFalse(ordinals.contains(ordinal), "Duplicate ordinal \(ordinal) for kind \(kind)")
            ordinals.insert(ordinal)
        }
        XCTAssertEqual(ordinals.count, allKinds.count)
    }

    // MARK: - String Table Deduplication

    func testStringTableDeduplicates() {
        // Two records with the same fqName should share a string table entry.
        let records = [
            MetadataRecord(kind: .class, mangledName: "m1", fqName: "test.Same"),
            MetadataRecord(kind: .interface, mangledName: "m2", fqName: "test.Same"),
        ]
        let data = RuntimeReflectionMetadataEmitter.serialize(records)
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertEqual(decoded?[0].fqName, "test.Same")
        XCTAssertEqual(decoded?[1].fqName, "test.Same")

        // Both should have the same simpleName.
        XCTAssertEqual(decoded?[0].simpleName, "Same")
        XCTAssertEqual(decoded?[1].simpleName, "Same")
    }

    // MARK: - Sentinel Values

    func testOptionalFieldsSentinel() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK",
            fqName: "test.fn",
            // No superFQName, fieldCount, instanceSizeWords
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 1)

        let r = decoded![0]
        XCTAssertNil(r.superFqName)
        XCTAssertNil(r.fieldCount)
        XCTAssertNil(r.instanceSizeWords)
    }

    // MARK: - Record Size Consistency

    func testRecordSizeIs24Bytes() {
        // Each record in the binary format should be exactly 24 bytes.
        XCTAssertEqual(RuntimeReflectionMetadataEmitter.recordSize, 24)
    }

    func testDataSizeWithOneRecord() {
        let record = MetadataRecord(kind: .class, mangledName: "m1", fqName: "test.Foo")
        let data = RuntimeReflectionMetadataEmitter.serialize([record])

        // Header: 16 bytes
        // Records: 24 bytes
        // String table header: 4 bytes
        // Strings: "test.Foo" (4 + 8 = 12 bytes) + "Foo" (4 + 3 = 7 bytes)
        let expectedSize = 16 + 24 + 4 + 12 + 7
        XCTAssertEqual(data.count, expectedSize)
    }

    // MARK: - Decoder Error Cases

    func testDecodeRejectsEmptyData() {
        let result = RuntimeReflectionMetadataDecoder.decode(Data())
        XCTAssertNil(result)
    }

    func testDecodeRejectsWrongMagic() {
        var data = Data(count: 20)
        // Wrong magic
        data[0] = 0x00
        data[1] = 0x00
        data[2] = 0x00
        data[3] = 0x00
        let result = RuntimeReflectionMetadataDecoder.decode(data)
        XCTAssertNil(result)
    }

    func testDecodeRejectsWrongVersion() {
        var data = RuntimeReflectionMetadataEmitter.serialize([])
        // Overwrite version field with 99
        let versionOffset = 4
        data[versionOffset] = 99
        data[versionOffset + 1] = 0
        data[versionOffset + 2] = 0
        data[versionOffset + 3] = 0
        let result = RuntimeReflectionMetadataDecoder.decode(data)
        XCTAssertNil(result)
    }

    // MARK: - Simple Name Extraction

    func testSimpleNameExtractionFromFQName() {
        let record = MetadataRecord(kind: .class, mangledName: "m1", fqName: "com.example.pkg.MyClass")
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertEqual(decoded?[0].simpleName, "MyClass")
        XCTAssertEqual(decoded?[0].fqName, "com.example.pkg.MyClass")
    }

    func testSimpleNameForTopLevelFunction() {
        let record = MetadataRecord(kind: .function, mangledName: "m1", fqName: "main")
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        // When there's no dot, simpleName == fqName.
        XCTAssertEqual(decoded?[0].simpleName, "main")
        XCTAssertEqual(decoded?[0].fqName, "main")
    }

    // MARK: - Sealed/Value Class Flags

    func testSealedClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK",
            fqName: "test.Shape",
            isSealedClass: true,
            sealedSubclassFQNames: ["test.Circle", "test.Rect"]
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        let sealedFlags = decoded![0].flags
        XCTAssertEqual(sealedFlags & (1 << 1), 1 << 1, "sealed bit should be set")
    }

    func testValueClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK",
            fqName: "test.Wrapper",
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I"
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        let valueFlags = decoded![0].flags
        XCTAssertEqual(valueFlags & (1 << 2), 1 << 2, "valueClass bit should be set")
    }

    // MARK: - Arity Clamping

    func testArityClampedToU16Max() {
        // Arity larger than UInt16.max should be clamped.
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK",
            fqName: "test.manyParams",
            arity: 100_000
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?[0].arity, UInt16.max)
    }

    // MARK: - Enum Class and Annotation Class Kinds

    func testEnumClassKindOrdinal() {
        let record = MetadataRecord(
            kind: .enumClass,
            mangledName: "_KK",
            fqName: "test.Color",
            declaredFieldCount: 3
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?[0].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.enumClass))
        XCTAssertEqual(decoded?[0].fieldCount, 3)
    }

    func testAnnotationClassKindOrdinal() {
        let record = MetadataRecord(
            kind: .annotationClass,
            mangledName: "_KK",
            fqName: "test.MyAnnotation"
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?[0].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.annotationClass))
    }
}
