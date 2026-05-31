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
/// The serialized metadata blob is emitted as per-word i64 globals because the
/// current LLVM bindings do not expose `LLVMConstArray` for i8 arrays.
///
/// Globals emitted:
/// - `<symbolPrefix>_?kk_reflection_metadata_size` (i64): total byte count of the serialized blob
/// - `<symbolPrefix>_?kk_reflection_metadata_words` (i64): number of i64 words
/// - `<symbolPrefix>_?kk_reflection_metadata_w{N}` (i64): each word of the blob (little-endian packed)
///
/// Layout:
/// ```
/// [4 bytes] magic: "KKRM" (0x4D524B4B)
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
struct RuntimeReflectionMetadataEmitter {
    /// Magic bytes: "KKRM"
    static let magic: UInt32 = 0x4D52_4B4B

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
    static func serialize(_ records: [MetadataRecord]) -> Data {
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
            appendU16(&data, saturatingUInt16(record.arity))
            appendU32(&data, idx.fqNameIndex)
            appendU32(&data, idx.simpleNameIndex)
            appendU32(&data, idx.superFqNameIndex)
            appendU32(&data, record.declaredFieldCount.map(saturatingUInt32) ?? sentinel)
            appendU32(&data, record.declaredInstanceSizeWords.map(saturatingUInt32) ?? sentinel)
        }

        // String table
        stringTable.appendTo(&data)

        return data
    }

    // MARK: - LLVM Emission

    /// Emits the serialized metadata as LLVM global constants using the
    /// provided bindings.
    ///
/// Creates the following globals:
/// - `<symbolPrefix>_?kk_reflection_metadata_size`: i64 holding the byte count
/// - `<symbolPrefix>_?kk_reflection_metadata_words`: i64 holding the number of i64 words
/// - `<symbolPrefix>_?kk_reflection_metadata_w{N}`: one i64 per word of the blob
    static func emitGlobals(
        records: [MetadataRecord],
        bindings: LLVMCAPIBindings,
        module: LLVMCAPIBindings.LLVMModuleRef,
        context _: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        symbolPrefix: String? = nil
    ) {
        let data = serialize(records)
        let byteCount = data.count
        let wordCount = (byteCount + 7) / 8
        let namePrefix = metadataSymbolPrefix(symbolPrefix)

        // Emit the size global.
        if let sizeGlobal = bindings.addGlobal(
            module: module,
            type: int64Type,
            name: "\(namePrefix)kk_reflection_metadata_size"
        ) {
            bindings.setExternalLinkage(sizeGlobal)
            if let sizeValue = bindings.constInt(int64Type, value: UInt64(byteCount)) {
                bindings.setInitializer(sizeGlobal, value: sizeValue)
            }
        }

        if let countGlobal = bindings.addGlobal(
            module: module,
            type: int64Type,
            name: "\(namePrefix)kk_reflection_metadata_words"
        ) {
            bindings.setExternalLinkage(countGlobal)
            if let countValue = bindings.constInt(int64Type, value: UInt64(wordCount)) {
                bindings.setInitializer(countGlobal, value: countValue)
            }
        }

        // Emit the metadata blob as a global byte array.
        // We store the metadata as an array of i64 values (padded to 8-byte alignment)
        // because i8 array types are not available through the current binding surface.
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
        for (i, word) in words.enumerated() {
            let name = "\(namePrefix)kk_reflection_metadata_w\(i)"
            if let wordGlobal = bindings.addGlobal(module: module, type: int64Type, name: name) {
                bindings.setExternalLinkage(wordGlobal)
                if let wordValue = bindings.constInt(int64Type, value: word) {
                    bindings.setInitializer(wordGlobal, value: wordValue)
                }
            }
        }
    }

    // MARK: - Binary Helpers

    private static func appendU16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func appendU32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func saturatingUInt16(_ value: Int) -> UInt16 {
        return UInt16(min(max(0, value), Int(UInt16.max)))
    }

    private static func saturatingUInt32(_ value: Int) -> UInt32 {
        return UInt32(min(max(0, value), Int(UInt32.max)))
    }

    private static func metadataSymbolPrefix(_ moduleName: String?) -> String {
        guard let moduleName, !moduleName.isEmpty else { return "" }
        let normalized = moduleName.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
        let stripped = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !stripped.isEmpty else { return "" }
        return "\(stripped)__"
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
            withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }

            // Each entry: length + UTF-8 bytes
            for string in strings {
                var length = UInt32(string.utf8.count).littleEndian
                withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
                data.append(contentsOf: string.utf8)
            }
        }
    }
}

// MARK: - Runtime Metadata Decoder (for testing/validation)

/// Decodes the binary reflection metadata format produced by
/// `RuntimeReflectionMetadataEmitter.serialize(_:)`.
/// This is primarily used for round-trip testing.
struct RuntimeReflectionMetadataDecoder {
    struct DecodedRecord {
        let kindOrdinal: UInt8
        let flags: UInt8
        let arity: UInt16
        let fqName: String
        let simpleName: String
        let superFqName: String?
        let fieldCount: UInt32?
        let instanceSizeWords: UInt32?
    }

    /// Decodes the binary metadata blob into decoded records.
    static func decode(_ data: Data) -> [DecodedRecord]? {
        guard data.count >= 16 else { return nil }
        var offset = 0

        let magic = readU32(data, at: &offset)
        guard magic == RuntimeReflectionMetadataEmitter.magic else { return nil }

        let version = readU32(data, at: &offset)
        guard version == RuntimeReflectionMetadataEmitter.version else { return nil }

        let recordCount = readU32(data, at: &offset)
        let stringTableOffset = readU32(data, at: &offset)
        let recordSize = UInt64(RuntimeReflectionMetadataEmitter.recordSize)
        let recordsSizeInBytes = UInt64(recordCount) * recordSize
        guard recordsSizeInBytes <= UInt64(Int.max) else { return nil }
        let recordsSize = Int(recordsSizeInBytes)
        let recordBytesEnd = 16 + recordsSize

        let stringTableOffsetInt = Int(stringTableOffset)
        guard stringTableOffsetInt <= data.count,
              stringTableOffsetInt >= recordBytesEnd
        else { return nil }

        // Decode string table first.
        let strings = decodeStringTable(data, at: stringTableOffsetInt)
        guard let strings else { return nil }

        var records: [DecodedRecord] = []
        let recordIterations = Int(recordCount)
        for _ in 0..<recordIterations {
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

            guard Int(fqNameIdx) < strings.count, Int(simpleNameIdx) < strings.count else {
                // Invalid string table index — metadata blob is corrupted.
                return nil
            }
            let fqName = strings[Int(fqNameIdx)]
            let simpleName = strings[Int(simpleNameIdx)]
            let superFqName: String?
            if superFqNameIdx == RuntimeReflectionMetadataEmitter.sentinel {
                superFqName = nil
            } else {
                guard Int(superFqNameIdx) < strings.count else {
                    return nil
                }
                superFqName = strings[Int(superFqNameIdx)]
            }
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
            let str = String(decoding: stringData, as: UTF8.self)
            guard stringData.elementsEqual(str.utf8) else { return nil }
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
