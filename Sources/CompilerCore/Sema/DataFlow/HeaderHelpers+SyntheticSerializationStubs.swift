import Foundation

/// Synthetic stdlib stubs for kotlinx.serialization.json.Json (STDLIB-SER-132).
/// Registers the Json object and its encodeToString / decodeFromString methods.
extension DataFlowSemaPhase {
    func registerSyntheticSerializationStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Ensure package hierarchy: kotlinx.serialization.json
        let jsonPkg = ensurePackage(
            path: ["kotlinx", "serialization", "json"],
            symbols: symbols,
            interner: interner
        )

        let stringType = types.stringType
        let anyType = types.anyType

        // --- Json class symbol ---
        let jsonClassSymbol = ensureClassSymbol(
            named: "Json",
            in: jsonPkg,
            symbols: symbols,
            interner: interner
        )
        let jsonType = types.make(.classType(ClassType(
            classSymbol: jsonClassSymbol,
            args: [],
            nullability: .nonNull
        )))

        // --- Json.Default companion ---
        let companionFQName = ensureJsonDefaultCompanion(
            ownerSymbol: jsonClassSymbol,
            jsonType: jsonType,
            symbols: symbols,
            interner: interner
        )

        // --- Json.encodeToString(value: Any): String  (companion method) ---
        registerJsonCompanionMethod(
            named: "encodeToString",
            externalLinkName: "kk_json_encodeToString",
            returnType: stringType,
            parameters: [(name: "value", type: anyType)],
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- Json.decodeFromString(string: String): Any  (companion method, can throw) ---
        registerJsonCompanionMethod(
            named: "decodeFromString",
            externalLinkName: "kk_json_decodeFromString",
            returnType: anyType,
            parameters: [(name: "string", type: stringType)],
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- Json.encodeToString(map: Map): String instance method ---
        registerJsonInstanceMethod(
            named: "encodeToString",
            externalLinkName: "kk_json_encodeMapToString",
            returnType: stringType,
            parameters: [(name: "value", type: anyType)],
            ownerSymbol: jsonClassSymbol,
            ownerType: jsonType,
            symbols: symbols,
            interner: interner
        )

        // --- Json.decodeFromString(string: String): Any instance method ---
        registerJsonInstanceMethod(
            named: "decodeFromString",
            externalLinkName: "kk_json_decodeFromString",
            returnType: anyType,
            parameters: [(name: "string", type: stringType)],
            ownerSymbol: jsonClassSymbol,
            ownerType: jsonType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Serialization Helpers

    private func ensureJsonDefaultCompanion(
        ownerSymbol: SymbolID,
        jsonType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if let existingCompanion = symbols.companionObjectSymbol(for: ownerSymbol),
           let companionInfo = symbols.symbol(existingCompanion)
        {
            return companionInfo.fqName
        }

        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return []
        }

        let companionName = interner.intern("Default")
        let companionFQName = ownerInfo.fqName + [companionName]
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)

        // Also register the Json.Default property on the companion
        let defaultName = interner.intern("Default")
        let defaultFQName = companionFQName + [defaultName]
        if symbols.lookup(fqName: defaultFQName) == nil {
            let defaultSymbol = symbols.define(
                kind: .property,
                name: defaultName,
                fqName: defaultFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(companionSymbol, for: defaultSymbol)
            symbols.setPropertyType(jsonType, for: defaultSymbol)
            symbols.setExternalLinkName("kk_json_default", for: defaultSymbol)
        }

        return companionFQName
    }

    private func registerJsonCompanionMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        companionFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = companionFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) == nil else {
            return
        }

        guard let companionSymbol = symbols.lookup(fqName: companionFQName) else {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(companionSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerJsonInstanceMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType &&
                existingSignature.receiverType == ownerType
        }) == nil else {
            return
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }
}
