import Foundation

extension DataFlowSemaPassPhase {
    func parseLibraryMetadata(
        path: String,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) -> [ImportedLibrarySymbolRecord]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0001",
                "Unable to read library metadata: \(path)",
                range: nil
            )
            return nil
        }

        var records: [ImportedLibrarySymbolRecord] = []
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("symbols=") {
                continue
            }
            let parts = line.split(separator: " ").map(String.init)
            guard let kindToken = parts.first,
                  let kind = symbolKindFromMetadata(kindToken) else {
                continue
            }
            let mangledName = parts.count > 1 ? parts[1] : ""

            var fqName: [InternedString] = []
            var arity = 0
            var isSuspend = false
            var isInline = false
            var typeSignature: String? = nil
            var externalLinkName: String? = nil
            var declaredFieldCount: Int? = nil
            var declaredInstanceSizeWords: Int? = nil
            var declaredVtableSize: Int? = nil
            var declaredItableSize: Int? = nil
            var superFQName: [InternedString]? = nil
            var fieldOffsets: [ImportedFieldOffsetEntry] = []
            var vtableSlots: [ImportedVTableSlotEntry] = []
            var itableSlots: [ImportedITableSlotEntry] = []

            for part in parts.dropFirst() {
                guard let separatorIndex = part.firstIndex(of: "=") else {
                    continue
                }
                let key = String(part[..<separatorIndex])
                let value = String(part[part.index(after: separatorIndex)...])
                switch key {
                case "fq":
                    fqName = value
                        .split(separator: ".")
                        .map { interner.intern(String($0)) }
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
                    let parsed = value
                        .split(separator: ".")
                        .map { interner.intern(String($0)) }
                    superFQName = parsed.isEmpty ? nil : parsed
                case "fieldOffsets":
                    fieldOffsets = parseImportedFieldOffsets(
                        token: value,
                        diagnostics: diagnostics,
                        metadataPath: path,
                        ownerFQName: fqName,
                        interner: interner
                    )
                case "vtableSlots":
                    vtableSlots = parseImportedVTableSlots(
                        token: value,
                        diagnostics: diagnostics,
                        metadataPath: path,
                        ownerFQName: fqName,
                        interner: interner
                    )
                case "itableSlots":
                    itableSlots = parseImportedITableSlots(
                        token: value,
                        diagnostics: diagnostics,
                        metadataPath: path,
                        ownerFQName: fqName,
                        interner: interner
                    )
                default:
                    continue
                }
            }

            guard !fqName.isEmpty else {
                continue
            }
            records.append(ImportedLibrarySymbolRecord(
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
                itableSlots: itableSlots
            ))
        }

        return records
    }

    func importedFunctionSignature(
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String
    ) -> FunctionSignature {
        let fallback = FunctionSignature(
            parameterTypes: Array(repeating: types.anyType, count: max(0, record.arity)),
            returnType: types.anyType,
            isSuspend: record.isSuspend
        )
        guard let encodedSignature = record.typeSignature else {
            return fallback
        }
        guard let decoded = decodeImportedTypeSignature(
            token: encodedSignature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: record.fqName
        ) else {
            return fallback
        }
        guard case .functionType(let functionType) = types.kind(of: decoded) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0003",
                "Invalid function signature metadata at \(metadataPath): \(renderFQName(record.fqName, interner: interner))",
                range: nil
            )
            return fallback
        }
        if record.arity != functionType.params.count || record.isSuspend != functionType.isSuspend {
            diagnostics.warning(
                "KSWIFTK-LIB-0005",
                "Metadata signature/arity mismatch at \(metadataPath): \(renderFQName(record.fqName, interner: interner))",
                range: nil
            )
        }
        return FunctionSignature(
            receiverType: functionType.receiver,
            parameterTypes: functionType.params,
            returnType: functionType.returnType,
            isSuspend: functionType.isSuspend
        )
    }

    func importedPropertyType(
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String
    ) -> TypeID {
        guard let encodedSignature = record.typeSignature else {
            return types.anyType
        }
        return decodeImportedTypeSignature(
            token: encodedSignature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: record.fqName
        ) ?? types.anyType
    }

    func importedTypeAliasUnderlyingType(
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String
    ) -> TypeID? {
        guard let encodedSignature = record.typeSignature else {
            return nil
        }
        guard let decoded = decodeImportedTypeSignature(
            token: encodedSignature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: record.fqName
        ) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0003",
                "Invalid typealias signature metadata at \(metadataPath): \(renderFQName(record.fqName, interner: interner))",
                range: nil
            )
            return nil
        }
        if case .error = types.kind(of: decoded) {
            diagnostics.warning(
                "KSWIFTK-LIB-0006",
                "Inconsistent typealias metadata at \(metadataPath): underlying type for '\(renderFQName(record.fqName, interner: interner))' resolved to error type.",
                range: nil
            )
            return decoded
        }
        return decoded
    }

    private func decodeImportedTypeSignature(
        token: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString]
    ) -> TypeID? {
        var parser = MetadataTypeSignatureParser(
            source: token,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName
        )
        return parser.parse()
    }

    private struct MetadataTypeSignatureParser {
        private let source: [Character]
        private var index: Int
        private let symbols: SymbolTable
        private let types: TypeSystem
        private let interner: StringInterner
        private let diagnostics: DiagnosticEngine
        private let metadataPath: String
        private let ownerFQName: [InternedString]
        private let syntheticTypeParameterBase: Int32 = DataFlowSemaPassPhase.syntheticTypeParameterBase

        init(
            source: String,
            symbols: SymbolTable,
            types: TypeSystem,
            interner: StringInterner,
            diagnostics: DiagnosticEngine,
            metadataPath: String,
            ownerFQName: [InternedString]
        ) {
            self.source = Array(source)
            self.index = 0
            self.symbols = symbols
            self.types = types
            self.interner = interner
            self.diagnostics = diagnostics
            self.metadataPath = metadataPath
            self.ownerFQName = ownerFQName
        }

        mutating func parse() -> TypeID? {
            guard let type = parseType(), index == source.count else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Malformed type signature in metadata at \(metadataPath): \(String(source)) (\(ownerName()))",
                    range: nil
                )
                return nil
            }
            return type
        }

        private mutating func parseType() -> TypeID? {
            if consume(prefix: "Q<") {
                guard let inner = parseType(), consume(character: ">") else {
                    return nil
                }
                return makeNullable(inner)
            }
            if consume(prefix: "SF"), let next = peek(), next.isNumber {
                return parseFunctionType(isSuspend: true)
            }
            if consume(character: "F") {
                if let next = peek(), next.isNumber {
                    return parseFunctionType(isSuspend: false)
                }
                return types.make(.primitive(.float, .nonNull))
            }
            if consume(character: "E") {
                return types.errorType
            }
            if consume(character: "U") {
                return types.unitType
            }
            if consume(character: "N") {
                return types.nothingType
            }
            if consume(character: "A") {
                return types.anyType
            }
            if consume(character: "Z") {
                return types.make(.primitive(.boolean, .nonNull))
            }
            if consume(character: "C") {
                return types.make(.primitive(.char, .nonNull))
            }
            if consume(character: "I") {
                return types.make(.primitive(.int, .nonNull))
            }
            if consume(character: "J") {
                return types.make(.primitive(.long, .nonNull))
            }
            if consume(character: "D") {
                return types.make(.primitive(.double, .nonNull))
            }
            if consume(character: "L") {
                return parseClassType()
            }
            if consume(character: "T") {
                return parseTypeParameterType()
            }
            if consume(prefix: "X<") {
                return parseIntersectionType()
            }
            return nil
        }

        private mutating func parseClassType() -> TypeID? {
            let name = parseUntilDelimiters(["<", ";"])
            guard !name.isEmpty else {
                return nil
            }

            var args: [TypeArg] = []
            if consume(character: "<") {
                while true {
                    guard let arg = parseTypeArg() else {
                        return nil
                    }
                    args.append(arg)
                    if consume(character: ">") {
                        break
                    }
                    guard consume(character: ",") else {
                        return nil
                    }
                }
            }
            guard consume(character: ";") else {
                return nil
            }
            if name == "kotlin_String" {
                return types.make(.primitive(.string, .nonNull))
            }

            let fqName = name.split(separator: ".").map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                return nil
            }
            let candidates = symbols.lookupAll(fqName: fqName)
                .compactMap { symbols.symbol($0) }
                .filter { symbol in
                    switch symbol.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass:
                        return true
                    default:
                        return false
                    }
                }
                .sorted(by: { $0.id.rawValue < $1.id.rawValue })
            guard let classSymbol = candidates.first?.id else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0004",
                    "Unknown nominal type in metadata signature at \(metadataPath): \(name) (\(ownerName()))",
                    range: nil
                )
                return types.anyType
            }
            return types.make(.classType(ClassType(classSymbol: classSymbol, args: args, nullability: .nonNull)))
        }

        private mutating func parseTypeArg() -> TypeArg? {
            if consume(character: "*") {
                return .star
            }
            if consume(prefix: "O<") {
                guard let type = parseType(), consume(character: ">") else {
                    return nil
                }
                return .out(type)
            }
            if consume(prefix: "N<") {
                guard let type = parseType(), consume(character: ">") else {
                    return nil
                }
                return .in(type)
            }
            guard let type = parseType() else {
                return nil
            }
            return .invariant(type)
        }

        private mutating func parseFunctionType(isSuspend: Bool) -> TypeID? {
            guard let arity = parseNumber(), consume(character: "<") else {
                return nil
            }

            var receiver: TypeID?
            if consume(character: "R") {
                guard let receiverType = parseType(), consume(character: ",") else {
                    return nil
                }
                receiver = receiverType
            }

            var params: [TypeID] = []
            params.reserveCapacity(arity)
            for _ in 0..<arity {
                guard let parameterType = parseType() else {
                    return nil
                }
                params.append(parameterType)
                guard consume(character: ",") else {
                    return nil
                }
            }

            guard let returnType = parseType(), consume(character: ">") else {
                return nil
            }
            return types.make(.functionType(FunctionType(
                receiver: receiver,
                params: params,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: .nonNull
            )))
        }

        private mutating func parseTypeParameterType() -> TypeID? {
            guard let rawIndex = parseNumber() else {
                return nil
            }
            let rawSymbol = syntheticTypeParameterBase - Int32(truncatingIfNeeded: rawIndex)
            return types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: rawSymbol), nullability: .nonNull)))
        }

        private mutating func parseIntersectionType() -> TypeID? {
            var parts: [TypeID] = []
            while true {
                guard let type = parseType() else {
                    return nil
                }
                parts.append(type)
                if consume(character: ">") {
                    break
                }
                guard consume(character: "&") else {
                    return nil
                }
            }
            return types.make(.intersection(parts))
        }

        private func makeNullable(_ type: TypeID) -> TypeID {
            switch types.kind(of: type) {
            case .any:
                return types.nullableAnyType
            case .primitive(let primitive, _):
                return types.make(.primitive(primitive, .nullable))
            case .classType(let classType):
                return types.make(.classType(ClassType(
                    classSymbol: classType.classSymbol,
                    args: classType.args,
                    nullability: .nullable
                )))
            case .typeParam(let typeParam):
                return types.make(.typeParam(TypeParamType(symbol: typeParam.symbol, nullability: .nullable)))
            case .functionType(let functionType):
                return types.make(.functionType(FunctionType(
                    receiver: functionType.receiver,
                    params: functionType.params,
                    returnType: functionType.returnType,
                    isSuspend: functionType.isSuspend,
                    nullability: .nullable
                )))
            default:
                return types.nullableAnyType
            }
        }

        private mutating func parseNumber() -> Int? {
            let start = index
            while let ch = peek(), ch.isNumber {
                index += 1
            }
            guard index > start else {
                return nil
            }
            return Int(String(source[start..<index]))
        }

        private mutating func parseUntilDelimiters(_ delimiters: Set<Character>) -> String {
            let start = index
            while let ch = peek(), !delimiters.contains(ch) {
                index += 1
            }
            return String(source[start..<index])
        }

        private func peek() -> Character? {
            guard index < source.count else {
                return nil
            }
            return source[index]
        }

        private mutating func consume(prefix: String) -> Bool {
            let chars = Array(prefix)
            guard index + chars.count <= source.count else {
                return false
            }
            for (offset, ch) in chars.enumerated() {
                if source[index + offset] != ch {
                    return false
                }
            }
            index += chars.count
            return true
        }

        private mutating func consume(character: Character) -> Bool {
            guard let ch = peek(), ch == character else {
                return false
            }
            index += 1
            return true
        }

        private func ownerName() -> String {
            ownerFQName.map { interner.resolve($0) }.joined(separator: ".")
        }
    }
}
