import Foundation

// MARK: - Runtime Reflection Metadata Emitter (REFL-004)

/// Emits runtime-accessible reflection metadata as LLVM global constants.
///
/// The emitted metadata enables `KClass` instances to query type information
/// (simpleName, qualifiedName, supertypes, member counts, flags) at runtime
/// without requiring the compile-time `.kklib` metadata files.
///
/// ## Binary Format
///
/// The metadata is emitted as a flat byte buffer stored in a global constant
/// named `kk_reflection_metadata`. A companion global `kk_reflection_metadata_size`
/// holds the byte count.
///
/// Layout:
/// ```
/// [4 bytes] magic: "KKRM" (0x4B4B524D)
/// [4 bytes] version: 1 (little-endian u32)
/// [4 bytes] record_count (little-endian u32)
/// [4 bytes] string_table_offset (little-endian u32)
/// For each record:
///   [1 byte]  kind (SymbolKind ordinal)
///   [1 byte]  flags (bit 0=dataClass, bit 1=sealedClass, bit 2=valueClass,
///                     bit 3=suspend, bit 4=inline)
///   [2 bytes] arity (little-endian u16)
///   [4 bytes] fqName string table index (little-endian u32)
///   [4 bytes] simpleName string table index (little-endian u32)
///   [4 bytes] superFqName string table index (little-endian u32, 0xFFFFFFFF if none)
///   [4 bytes] fieldCount (little-endian u32, 0xFFFFFFFF if unknown)
///   [4 bytes] instanceSizeWords (little-endian u32, 0xFFFFFFFF if unknown)
/// String table:
///   [4 bytes] entry count (little-endian u32)
///   For each entry:
///     [4 bytes] length in bytes (little-endian u32)
///     [N bytes] UTF-8 string data (NOT null-terminated)
/// ```
public struct RuntimeReflectionMetadataEmitter {
    /// Magic bytes: "KKRM"
    static let magic: UInt32 = 0x4B4B_524D

    /// Format version
    static let version: UInt32 = 1

    /// Sentinel for "no value" in u32 fields.
    static let sentinel: UInt32 = 0xFFFF_FFFF

    /// Size of a single record in bytes.
    static let recordSize = 24

    // MARK: - Kind Encoding

    /// Maps SymbolKind to a stable ordinal for binary encoding.
    static func kindOrdinal(_ kind: SymbolKind) -> UInt8 {
        switch kind {
        case .package: return 0
        case .class: return 1
        case .interface: return 2
        case .object: return 3
        case .enumClass: return 4
        case .annotationClass: return 5
        case .typeAlias: return 6
        case .function: return 7
        case .constructor: return 8
        case .property: return 9
        case .field: return 10
        case .backingField: return 11
        case .typeParameter: return 12
        case .valueParameter: return 13
        case .local: return 14
        case .label: return 15
        }
    }

    // MARK: - Flags Encoding

    static func encodeFlags(_ record: MetadataRecord) -> UInt8 {
        var flags: UInt8 = 0
        if record.isDataClass { flags |= 1 << 0 }
        if record.isSealedClass { flags |= 1 << 1 }
        if record.isValueClass { flags |= 1 << 2 }
        if record.isSuspend { flags |= 1 << 3 }
        if record.isInline { flags |= 1 << 4 }
        return flags
    }

    // MARK: - Serialization

    /// Serializes metadata records into a flat binary buffer suitable for
    /// embedding as a global constant in the compiled binary.
    public static func serialize(_ records: [MetadataRecord]) -> Data {
        var stringTable = StringTable()

        // Pre-register all strings so indices are stable.
        struct RecordIndices {
            let fqNameIndex: UInt32
            let simpleNameIndex: UInt32
            let superFqNameIndex: UInt32
        }

        let indices: [RecordIndices] = records.map { record in
            let fqIdx = stringTable.intern(record.fqName)
            let simpleName = record.fqName.split(separator: ".").last.map(String.init) ?? record.fqName
            let simpleIdx = stringTable.intern(simpleName)
            let superIdx: UInt32
            if let superFq = record.superFQName {
                superIdx = stringTable.intern(superFq)
            } else {
                superIdx = sentinel
            }
            return RecordIndices(fqNameIndex: fqIdx, simpleNameIndex: simpleIdx, superFqNameIndex: superIdx)
        }

        // Calculate offsets.
        let headerSize = 16 // magic + version + record_count + string_table_offset
        let recordsSize = records.count * recordSize
        let stringTableOffset = UInt32(headerSize + recordsSize)

        var data = Data()
        data.reserveCapacity(headerSize + recordsSize + stringTable.estimatedSize)

        // Header
        appendU32(&data, magic)
        appendU32(&data, version)
        appendU32(&data, UInt32(records.count))
        appendU32(&data, stringTableOffset)

        // Records
        for (i, record) in records.enumerated() {
            let idx = indices[i]
            data.append(kindOrdinal(record.kind))
            data.append(encodeFlags(record))
            appendU16(&data, UInt16(min(record.arity, Int(UInt16.max))))
            appendU32(&data, idx.fqNameIndex)
            appendU32(&data, idx.simpleNameIndex)
            appendU32(&data, idx.superFqNameIndex)
            appendU32(&data, record.declaredFieldCount.map { UInt32($0) } ?? sentinel)
            appendU32(&data, record.declaredInstanceSizeWords.map { UInt32($0) } ?? sentinel)
        }

        // String table
        stringTable.appendTo(&data)

        return data
    }

    // MARK: - LLVM Emission

    /// Emits the serialized metadata as LLVM global constants using the
    /// provided bindings.
    ///
    /// Creates two globals:
    /// - `kk_reflection_metadata`: byte array containing the serialized metadata
    /// - `kk_reflection_metadata_size`: i64 holding the byte count
    ///
    /// Both are marked as internal linkage constants.
    static func emitGlobals(
        records: [MetadataRecord],
        bindings: LLVMCAPIBindings,
        module: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef
    ) {
        guard !records.isEmpty else { return }

        let data = serialize(records)
        let byteCount = data.count

        // Emit the size global.
        if let sizeGlobal = bindings.addGlobal(
            module: module,
            type: int64Type,
            name: "kk_reflection_metadata_size"
        ) {
            if let sizeValue = bindings.constInt(int64Type, value: UInt64(byteCount)) {
                bindings.setInitializer(sizeGlobal, value: sizeValue)
            }
        }

        // Emit the metadata blob as a global byte array.
        // We store the metadata as an array of i64 values (padded to 8-byte alignment)
        // because i8 array types are not available through the current binding surface.
        let wordCount = (byteCount + 7) / 8
        guard wordCount > 0 else { return }

        // Pack bytes into i64 words (little-endian).
        var words: [UInt64] = []
        words.reserveCapacity(wordCount)
        for wordIdx in 0 ..< wordCount {
            var word: UInt64 = 0
            for byteIdx in 0 ..< 8 {
                let offset = wordIdx * 8 + byteIdx
                if offset < byteCount {
                    word |= UInt64(data[offset]) << (byteIdx * 8)
                }
            }
            words.append(word)
        }

        // Emit each word as a separate named global for simplicity, since the
        // current LLVM bindings do not expose LLVMConstArray. A single "directory"
        // global holds the count, and indexed globals hold each word.
        if let countGlobal = bindings.addGlobal(
            module: module,
            type: int64Type,
            name: "kk_reflection_metadata_words"
        ) {
            if let countValue = bindings.constInt(int64Type, value: UInt64(wordCount)) {
                bindings.setInitializer(countGlobal, value: countValue)
            }
        }

        for (i, word) in words.enumerated() {
            let name = "kk_reflection_metadata_w\(i)"
            if let wordGlobal = bindings.addGlobal(module: module, type: int64Type, name: name) {
                if let wordValue = bindings.constInt(int64Type, value: word) {
                    bindings.setInitializer(wordGlobal, value: wordValue)
                }
            }
        }
    }

    // MARK: - Binary Helpers

    private static func appendU16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }

    private static func appendU32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }

    // MARK: - String Table

    struct StringTable {
        private var strings: [String] = []
        private var indexMap: [String: UInt32] = [:]

        var estimatedSize: Int {
            4 + strings.reduce(0) { $0 + 4 + $1.utf8.count }
        }

        mutating func intern(_ string: String) -> UInt32 {
            if let existing = indexMap[string] {
                return existing
            }
            let index = UInt32(strings.count)
            strings.append(string)
            indexMap[string] = index
            return index
        }

        func appendTo(_ data: inout Data) {
            // Entry count
            var count = UInt32(strings.count).littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })

            // Each entry: length + UTF-8 bytes
            for string in strings {
                let utf8 = Array(string.utf8)
                var length = UInt32(utf8.count).littleEndian
                data.append(contentsOf: withUnsafeBytes(of: &length) { Array($0) })
                data.append(contentsOf: utf8)
            }
        }
    }
}

// MARK: - Runtime Metadata Decoder (for testing/validation)

/// Decodes the binary reflection metadata format produced by
/// `RuntimeReflectionMetadataEmitter.serialize(_:)`.
/// This is primarily used for round-trip testing.
public struct RuntimeReflectionMetadataDecoder {
    public struct DecodedRecord {
        public let kindOrdinal: UInt8
        public let flags: UInt8
        public let arity: UInt16
        public let fqName: String
        public let simpleName: String
        public let superFqName: String?
        public let fieldCount: UInt32?
        public let instanceSizeWords: UInt32?
    }

    /// Decodes the binary metadata blob into decoded records.
    public static func decode(_ data: Data) -> [DecodedRecord]? {
        guard data.count >= 16 else { return nil }
        var offset = 0

        let magic = readU32(data, at: &offset)
        guard magic == RuntimeReflectionMetadataEmitter.magic else { return nil }

        let version = readU32(data, at: &offset)
        guard version == RuntimeReflectionMetadataEmitter.version else { return nil }

        let recordCount = readU32(data, at: &offset)
        let stringTableOffset = readU32(data, at: &offset)

        // Decode string table first.
        let strings = decodeStringTable(data, at: Int(stringTableOffset))
        guard let strings else { return nil }

        var records: [DecodedRecord] = []
        for _ in 0 ..< recordCount {
            guard offset + RuntimeReflectionMetadataEmitter.recordSize <= data.count else {
                return nil
            }
            let kind = data[offset]; offset += 1
            let flags = data[offset]; offset += 1
            let arity = readU16(data, at: &offset)
            let fqNameIdx = readU32(data, at: &offset)
            let simpleNameIdx = readU32(data, at: &offset)
            let superFqNameIdx = readU32(data, at: &offset)
            let fieldCountRaw = readU32(data, at: &offset)
            let instanceSizeRaw = readU32(data, at: &offset)

            let fqName = Int(fqNameIdx) < strings.count ? strings[Int(fqNameIdx)] : ""
            let simpleName = Int(simpleNameIdx) < strings.count ? strings[Int(simpleNameIdx)] : ""
            let superFqName: String? = superFqNameIdx == RuntimeReflectionMetadataEmitter.sentinel
                ? nil
                : (Int(superFqNameIdx) < strings.count ? strings[Int(superFqNameIdx)] : nil)
            let fieldCount: UInt32? = fieldCountRaw == RuntimeReflectionMetadataEmitter.sentinel ? nil : fieldCountRaw
            let instanceSize: UInt32? = instanceSizeRaw == RuntimeReflectionMetadataEmitter.sentinel ? nil : instanceSizeRaw

            records.append(DecodedRecord(
                kindOrdinal: kind,
                flags: flags,
                arity: arity,
                fqName: fqName,
                simpleName: simpleName,
                superFqName: superFqName,
                fieldCount: fieldCount,
                instanceSizeWords: instanceSize
            ))
        }
        return records
    }

    private static func decodeStringTable(_ data: Data, at startOffset: Int) -> [String]? {
        var offset = startOffset
        guard offset + 4 <= data.count else { return nil }

        let count = readU32(data, at: &offset)
        var strings: [String] = []
        strings.reserveCapacity(Int(count))

        for _ in 0 ..< count {
            guard offset + 4 <= data.count else { return nil }
            let length = readU32(data, at: &offset)
            let endIdx = offset + Int(length)
            guard endIdx <= data.count else { return nil }
            let stringData = data[offset ..< endIdx]
            guard let str = String(data: Data(stringData), encoding: .utf8) else { return nil }
            strings.append(str)
            offset = endIdx
        }
        return strings
    }

    private static func readU16(_ data: Data, at offset: inout Int) -> UInt16 {
        guard offset + 2 <= data.count else {
            offset += 2
            return 0
        }
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        offset += 2
        return b0 | (b1 << 8)
    }

    private static func readU32(_ data: Data, at offset: inout Int) -> UInt32 {
        guard offset + 4 <= data.count else {
            offset += 4
            return 0
        }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        offset += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
