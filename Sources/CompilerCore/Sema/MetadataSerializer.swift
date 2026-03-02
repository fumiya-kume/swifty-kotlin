import Foundation

// MARK: - Shared Metadata Record

/// Unified metadata record used by both export (MetadataEncoder) and import (MetadataDecoder).
/// This is the single source of truth for what information survives the metadata round-trip.
public struct MetadataRecord {
    public let kind: SymbolKind
    public let mangledName: String
    public let fqName: String
    public let arity: Int
    public let isSuspend: Bool
    public let isInline: Bool
    public let typeSignature: String?
    public let externalLinkName: String?
    public let declaredFieldCount: Int?
    public let declaredInstanceSizeWords: Int?
    public let declaredVtableSize: Int?
    public let declaredItableSize: Int?
    public let superFQName: String?
    public let fieldOffsets: String?
    public let vtableSlots: String?
    public let itableSlots: String?

    // P5-74: data class flag
    public let isDataClass: Bool

    // P5-74: sealed class flag
    public let isSealedClass: Bool

    // P5-86: annotation metadata
    public let annotations: [MetadataAnnotationRecord]

    // P5-75: value class flag
    public let isValueClass: Bool

    // P5-75: value class underlying type signature (e.g. "I" for Int)
    public let valueClassUnderlyingTypeSig: String?

    // P5-78: sealed subclass FQ names for cross-module exhaustiveness
    public let sealedSubclassFQNames: [String]

    public init(
        kind: SymbolKind,
        mangledName: String = "",
        fqName: String = "",
        arity: Int = 0,
        isSuspend: Bool = false,
        isInline: Bool = false,
        typeSignature: String? = nil,
        externalLinkName: String? = nil,
        declaredFieldCount: Int? = nil,
        declaredInstanceSizeWords: Int? = nil,
        declaredVtableSize: Int? = nil,
        declaredItableSize: Int? = nil,
        superFQName: String? = nil,
        fieldOffsets: String? = nil,
        vtableSlots: String? = nil,
        itableSlots: String? = nil,
        isDataClass: Bool = false,
        isSealedClass: Bool = false,
        annotations: [MetadataAnnotationRecord] = [],
        isValueClass: Bool = false,
        valueClassUnderlyingTypeSig: String? = nil,
        sealedSubclassFQNames: [String] = []
    ) {
        self.kind = kind
        self.mangledName = mangledName
        self.fqName = fqName
        self.arity = arity
        self.isSuspend = isSuspend
        self.isInline = isInline
        self.typeSignature = typeSignature
        self.externalLinkName = externalLinkName
        self.declaredFieldCount = declaredFieldCount
        self.declaredInstanceSizeWords = declaredInstanceSizeWords
        self.declaredVtableSize = declaredVtableSize
        self.declaredItableSize = declaredItableSize
        self.superFQName = superFQName
        self.fieldOffsets = fieldOffsets
        self.vtableSlots = vtableSlots
        self.itableSlots = itableSlots
        self.isDataClass = isDataClass
        self.isSealedClass = isSealedClass
        self.annotations = annotations
        self.isValueClass = isValueClass
        self.valueClassUnderlyingTypeSig = valueClassUnderlyingTypeSig
        self.sealedSubclassFQNames = sealedSubclassFQNames
    }
}

/// Annotation metadata that survives the export/import round-trip (P5-86).
public struct MetadataAnnotationRecord: Equatable {
    /// Fully-qualified name of the annotation class (e.g. "kotlin.Deprecated").
    public let annotationFQName: String
    /// Serialized argument values.
    public let arguments: [String]
    /// Optional use-site target (get, set, field, param, etc.).
    public let useSiteTarget: String?

    public init(
        annotationFQName: String,
        arguments: [String] = [],
        useSiteTarget: String? = nil
    ) {
        self.annotationFQName = annotationFQName
        self.arguments = arguments
        self.useSiteTarget = useSiteTarget
    }
}

// MARK: - MetadataEncoder (Export)

/// Encodes compiler symbols into `[MetadataRecord]` and serializes them to the text-based
/// metadata format consumed by `MetadataDecoder`.
public final class MetadataEncoder {
    public init() {}

    /// Build metadata records from the compiler's semantic state.
    public func buildRecords(
        symbols: SymbolTable,
        types: TypeSystem,
        moduleName: String,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String]
    ) -> [MetadataRecord] {
        let mangler = NameMangler()
        let exported = symbols.allSymbols()
            .filter { $0.visibility == .public && $0.kind != .package }
            .sorted { lhs, rhs in
                if lhs.fqName.count != rhs.fqName.count {
                    return lhs.fqName.count < rhs.fqName.count
                }
                let lhsRaw = lhs.fqName.map(\.rawValue)
                let rhsRaw = rhs.fqName.map(\.rawValue)
                if lhsRaw != rhsRaw {
                    return lhsRaw.lexicographicallyPrecedes(rhsRaw)
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }

        var records: [MetadataRecord] = []
        for symbol in exported {
            let mangled = mangler.mangle(
                moduleName: moduleName,
                symbol: symbol,
                symbols: symbols,
                types: types,
                nameResolver: { interner.resolve($0) }
            )
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")

            var arity = 0
            var isSuspend = false
            var isInline = false
            var typeSignature: String?
            var externalLinkName: String?

            if symbol.kind == .function || symbol.kind == .constructor, let signature = symbols.functionSignature(for: symbol.id) {
                arity = signature.parameterTypes.count
                isSuspend = signature.isSuspend
                isInline = symbol.flags.contains(.inlineFunction)
                typeSignature = mangler.mangledSignature(
                    for: symbol,
                    symbols: symbols,
                    types: types,
                    nameResolver: { interner.resolve($0) }
                )
                externalLinkName = functionLinkNames[symbol.id]
            }

            if symbol.kind == .property || symbol.kind == .field,
               symbols.propertyType(for: symbol.id) != nil
            {
                typeSignature = mangler.mangledSignature(
                    for: symbol,
                    symbols: symbols,
                    types: types,
                    nameResolver: { interner.resolve($0) }
                )
            }

            if symbol.kind == .typeAlias,
               symbols.typeAliasUnderlyingType(for: symbol.id) != nil
            {
                typeSignature = mangler.mangledSignature(
                    for: symbol,
                    symbols: symbols,
                    types: types,
                    nameResolver: { interner.resolve($0) }
                )
            }

            var declaredFieldCount: Int?
            var declaredInstanceSizeWords: Int?
            var declaredVtableSize: Int?
            var declaredItableSize: Int?
            var superFQName: String?
            var fieldOffsetsStr: String?
            var vtableSlotsStr: String?
            var itableSlotsStr: String?

            if Self.nominalKinds.contains(symbol.kind), let layout = symbols.nominalLayout(for: symbol.id) {
                declaredInstanceSizeWords = layout.instanceSizeWords
                declaredFieldCount = layout.instanceFieldCount
                declaredVtableSize = layout.vtableSize
                declaredItableSize = layout.itableSize

                let serializedFieldOffsets = serializeFieldOffsets(layout.fieldOffsets, symbols: symbols, interner: interner)
                if !serializedFieldOffsets.isEmpty {
                    fieldOffsetsStr = serializedFieldOffsets
                }
                let serializedVTableSlots = serializeVTableSlots(layout.vtableSlots, symbols: symbols, interner: interner)
                if !serializedVTableSlots.isEmpty {
                    vtableSlotsStr = serializedVTableSlots
                }
                let serializedITableSlots = serializeITableSlots(layout.itableSlots, symbols: symbols, interner: interner)
                if !serializedITableSlots.isEmpty {
                    itableSlotsStr = serializedITableSlots
                }
                if let superClass = layout.superClass,
                   let superSymbol = symbols.symbol(superClass)
                {
                    superFQName = superSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                }
            }

            let isDataClass = symbol.flags.contains(.dataType)
            let isSealedClass = symbol.flags.contains(.sealedType)
            let rawIsValueClass = symbol.flags.contains(.valueType)

            var valueClassUnderlyingTypeSig: String?
            if rawIsValueClass,
               let underlyingType = symbols.valueClassUnderlyingType(for: symbol.id)
            {
                valueClassUnderlyingTypeSig = mangler.encodeType(
                    underlyingType,
                    symbols: symbols,
                    types: types,
                    nameResolver: { interner.resolve($0) }
                )
            }

            // Only emit valueClass=1 when the underlying type is available;
            // without it, importers cannot resolve/unbox the value class.
            let isValueClass: Bool
            if rawIsValueClass, valueClassUnderlyingTypeSig == nil {
                assertionFailure(
                    "Value class '\(fqName)' is missing underlying type; omitting valueClass flag from metadata."
                )
                isValueClass = false
            } else {
                isValueClass = rawIsValueClass
            }

            let annotationEntries = symbols.annotations(for: symbol.id)

            // P5-78: collect sealed subclass FQ names for cross-module exhaustiveness
            var sealedSubclassFQNames: [String] = []
            if isSealedClass {
                let directSubs = symbols.sealedSubclasses(for: symbol.id) ?? symbols.directSubtypes(of: symbol.id)
                sealedSubclassFQNames = directSubs.compactMap { subID in
                    guard let subSymbol = symbols.symbol(subID) else { return nil }
                    let subFQ = subSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                    return subFQ.isEmpty ? nil : subFQ
                }.sorted()
            }

            records.append(MetadataRecord(
                kind: symbol.kind,
                mangledName: mangled,
                fqName: fqName,
                arity: arity,
                isSuspend: isSuspend,
                isInline: isInline,
                typeSignature: typeSignature,
                externalLinkName: externalLinkName,
                declaredFieldCount: declaredFieldCount,
                declaredInstanceSizeWords: declaredInstanceSizeWords,
                declaredVtableSize: declaredVtableSize,
                declaredItableSize: declaredItableSize,
                superFQName: superFQName,
                fieldOffsets: fieldOffsetsStr,
                vtableSlots: vtableSlotsStr,
                itableSlots: itableSlotsStr,
                isDataClass: isDataClass,
                isSealedClass: isSealedClass,
                annotations: annotationEntries,
                isValueClass: isValueClass,
                valueClassUnderlyingTypeSig: valueClassUnderlyingTypeSig,
                sealedSubclassFQNames: sealedSubclassFQNames
            ))
        }
        return records
    }

    /// Nominal kinds that carry layout information in metadata.
    private static let nominalKinds: Set<SymbolKind> = [.class, .interface, .object, .enumClass, .annotationClass]

    /// Serialize records to the text-based metadata format.
    public func serialize(_ records: [MetadataRecord]) -> String {
        var lines = ["symbols=\(records.count)"]
        for record in records {
            var fields: [String] = [
                "\(record.kind)",
                record.mangledName,
                "fq=\(record.fqName)",
                "schema=v1",
            ]
            if record.kind == .function || record.kind == .constructor {
                fields.append("arity=\(record.arity)")
                fields.append("suspend=\(record.isSuspend ? 1 : 0)")
                fields.append("inline=\(record.isInline ? 1 : 0)")
                if let sig = record.typeSignature {
                    fields.append("sig=\(sig)")
                }
                if let linkName = record.externalLinkName, !linkName.isEmpty {
                    fields.append("link=\(linkName)")
                }
            }
            if record.kind == .property || record.kind == .field {
                if let sig = record.typeSignature {
                    fields.append("sig=\(sig)")
                }
            }
            if record.kind == .typeAlias {
                if let sig = record.typeSignature {
                    fields.append("sig=\(sig)")
                }
            }
            if Self.nominalKinds.contains(record.kind) {
                if let layoutWords = record.declaredInstanceSizeWords {
                    fields.append("layoutWords=\(layoutWords)")
                }
                if let fieldCount = record.declaredFieldCount {
                    fields.append("fields=\(fieldCount)")
                }
                if let vtableSize = record.declaredVtableSize {
                    fields.append("vtable=\(vtableSize)")
                }
                if let itableSize = record.declaredItableSize {
                    fields.append("itable=\(itableSize)")
                }
                if let fo = record.fieldOffsets {
                    fields.append("fieldOffsets=\(fo)")
                }
                if let vs = record.vtableSlots {
                    fields.append("vtableSlots=\(vs)")
                }
                if let is_ = record.itableSlots {
                    fields.append("itableSlots=\(is_)")
                }
                if let superFq = record.superFQName {
                    fields.append("superFq=\(superFq)")
                }
            }
            if record.isDataClass {
                fields.append("dataClass=1")
            }
            if record.isSealedClass {
                fields.append("sealedClass=1")
            }
            if record.isValueClass {
                fields.append("valueClass=1")
                if let vSig = record.valueClassUnderlyingTypeSig {
                    fields.append("valueUnderlying=\(vSig)")
                }
            }
            if !record.sealedSubclassFQNames.isEmpty {
                fields.append("sealedSubs=\(record.sealedSubclassFQNames.joined(separator: ","))")
            }
            if !record.annotations.isEmpty {
                fields.append("annotations=\(encodeAnnotations(record.annotations))")
            }
            lines.append(fields.joined(separator: " "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Layout Serialization Helpers

    func serializeFieldOffsets(
        _ offsets: [SymbolID: Int],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        let pairs: [(String, Int)] = offsets.compactMap { symbolID, offset in
            guard let symbol = symbols.symbol(symbolID) else {
                return nil
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            guard !fqName.isEmpty else {
                return nil
            }
            return (fqName, offset)
        }
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        return sorted.map { "\($0.0)@\($0.1)" }.joined(separator: ",")
    }

    func serializeVTableSlots(
        _ slots: [SymbolID: Int],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        let pairs: [(String, Int)] = slots.compactMap { symbolID, slot in
            guard let symbol = symbols.symbol(symbolID), symbol.kind == .function else {
                return nil
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            guard !fqName.isEmpty else {
                return nil
            }
            let signature = symbols.functionSignature(for: symbolID)
            let arity = signature?.parameterTypes.count ?? 0
            let isSuspend = signature?.isSuspend ?? false
            let key = "\(fqName)#\(arity)#\(isSuspend ? 1 : 0)"
            return (key, slot)
        }
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        return sorted.map { "\($0.0)@\($0.1)" }.joined(separator: ",")
    }

    func serializeITableSlots(
        _ slots: [SymbolID: Int],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        let pairs: [(String, Int)] = slots.compactMap { symbolID, slot in
            guard let symbol = symbols.symbol(symbolID) else {
                return nil
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            guard !fqName.isEmpty else {
                return nil
            }
            return (fqName, slot)
        }
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        return sorted.map { "\($0.0)@\($0.1)" }.joined(separator: ",")
    }

    // MARK: - Annotation Encoding

    private func encodeAnnotations(_ annotations: [MetadataAnnotationRecord]) -> String {
        annotations.map { encodeAnnotation($0) }.joined(separator: ";")
    }

    private func encodeAnnotation(_ annotation: MetadataAnnotationRecord) -> String {
        var parts = [annotation.annotationFQName]
        if let target = annotation.useSiteTarget {
            parts.append("target:\(target)")
        }
        if !annotation.arguments.isEmpty {
            let argsB64 = annotation.arguments.map { Data($0.utf8).base64EncodedString() }
            parts.append("args:\(argsB64.joined(separator: ","))")
        }
        return parts.joined(separator: "|")
    }
}

// MARK: - MetadataDecoder (Import)

/// Decodes the text-based metadata format into `[MetadataRecord]`.
/// This replaces the ad-hoc parsing previously done in DataFlowSemaPass+LibraryMetadataParsing.
public final class MetadataDecoder {
    public init() {}

    /// Parse text content into metadata records.
    public func decode(_ content: String) -> [MetadataRecord] {
        var records: [MetadataRecord] = []
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("symbols=") {
                continue
            }
            let parts = line.split(separator: " ").map(String.init)
            guard let kindToken = parts.first,
                  let kind = symbolKindFromMetadata(kindToken)
            else {
                continue
            }
            let mangledName = parts.count > 1 ? parts[1] : ""

            var fqName = ""
            var arity = 0
            var isSuspend = false
            var isInline = false
            var typeSignature: String?
            var externalLinkName: String?
            var declaredFieldCount: Int?
            var declaredInstanceSizeWords: Int?
            var declaredVtableSize: Int?
            var declaredItableSize: Int?
            var superFQName: String?
            var fieldOffsets: String?
            var vtableSlots: String?
            var itableSlots: String?
            var isDataClass = false
            var isSealedClass = false
            var isValueClass = false
            var valueClassUnderlyingTypeSig: String?
            var annotations: [MetadataAnnotationRecord] = []
            var sealedSubclassFQNames: [String] = []
            var schemaVersion: String?

            for part in parts.dropFirst() {
                guard let separatorIndex = part.firstIndex(of: "=") else {
                    continue
                }
                let key = String(part[..<separatorIndex])
                let value = String(part[part.index(after: separatorIndex)...])
                switch key {
                case "fq":
                    fqName = value
                case "arity":
                    arity = Int(value) ?? 0
                case "suspend":
                    isSuspend = value == "1" || value == "true"
                case "inline":
                    isInline = value == "1" || value == "true"
                case "sig":
                    typeSignature = value.isEmpty ? nil : value
                case "link":
                    externalLinkName = value.isEmpty ? nil : value
                case "fields":
                    declaredFieldCount = Int(value)
                case "layoutWords":
                    declaredInstanceSizeWords = Int(value)
                case "vtable":
                    declaredVtableSize = Int(value)
                case "itable":
                    declaredItableSize = Int(value)
                case "superFq":
                    superFQName = value.isEmpty ? nil : value
                case "fieldOffsets":
                    fieldOffsets = value.isEmpty ? nil : value
                case "vtableSlots":
                    vtableSlots = value.isEmpty ? nil : value
                case "itableSlots":
                    itableSlots = value.isEmpty ? nil : value
                case "dataClass":
                    isDataClass = value == "1" || value == "true"
                case "sealedClass":
                    isSealedClass = value == "1" || value == "true"
                case "valueClass":
                    isValueClass = value == "1" || value == "true"
                case "valueUnderlying":
                    valueClassUnderlyingTypeSig = value.isEmpty ? nil : value
                case "sealedSubs":
                    sealedSubclassFQNames = value.split(separator: ",").map(String.init).filter { !$0.isEmpty }
                case "annotations":
                    annotations = decodeAnnotations(value)
                case "schema":
                    schemaVersion = value
                default:
                    continue
                }
            }

            // Strict schema gate: only v1 records are accepted.
            guard schemaVersion == "v1", !fqName.isEmpty else {
                continue
            }

            records.append(MetadataRecord(
                kind: kind,
                mangledName: mangledName,
                fqName: fqName,
                arity: arity,
                isSuspend: isSuspend,
                isInline: isInline,
                typeSignature: typeSignature,
                externalLinkName: externalLinkName,
                declaredFieldCount: declaredFieldCount,
                declaredInstanceSizeWords: declaredInstanceSizeWords,
                declaredVtableSize: declaredVtableSize,
                declaredItableSize: declaredItableSize,
                superFQName: superFQName,
                fieldOffsets: fieldOffsets,
                vtableSlots: vtableSlots,
                itableSlots: itableSlots,
                isDataClass: isDataClass,
                isSealedClass: isSealedClass,
                annotations: annotations,
                isValueClass: isValueClass,
                valueClassUnderlyingTypeSig: valueClassUnderlyingTypeSig,
                sealedSubclassFQNames: sealedSubclassFQNames
            ))
        }
        return records
    }

    // MARK: - Annotation Decoding

    private func decodeAnnotations(_ value: String) -> [MetadataAnnotationRecord] {
        guard !value.isEmpty else {
            return []
        }
        return value.split(separator: ";", omittingEmptySubsequences: true).compactMap { entry in
            decodeAnnotation(String(entry))
        }
    }

    private func decodeAnnotation(_ entry: String) -> MetadataAnnotationRecord? {
        let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let annotationFQName = parts.first, !annotationFQName.isEmpty else {
            return nil
        }
        var useSiteTarget: String?
        var arguments: [String] = []
        for part in parts.dropFirst() {
            if part.hasPrefix("target:") {
                useSiteTarget = String(part.dropFirst("target:".count))
            } else if part.hasPrefix("args:") {
                let argsStr = String(part.dropFirst("args:".count))
                arguments = argsStr.split(separator: ",", omittingEmptySubsequences: false).compactMap { b64 in
                    guard let data = Data(base64Encoded: String(b64)) else {
                        return nil
                    }
                    return String(data: data, encoding: .utf8)
                }
            }
        }
        return MetadataAnnotationRecord(
            annotationFQName: annotationFQName,
            arguments: arguments,
            useSiteTarget: useSiteTarget
        )
    }

    // MARK: - Symbol Kind Mapping

    func symbolKindFromMetadata(_ token: String) -> SymbolKind? {
        symbolKindFromMetadataToken(token)
    }
}
