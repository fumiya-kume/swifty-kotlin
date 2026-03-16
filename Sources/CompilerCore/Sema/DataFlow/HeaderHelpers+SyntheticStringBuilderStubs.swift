import Foundation

/// Synthetic stubs for StringBuilder type (STDLIB-255/256/257).
extension DataFlowSemaPhase {
    func registerSyntheticStringBuilderStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let sbSymbol = ensureClassSymbol(named: "StringBuilder", in: kotlinTextPkg, symbols: symbols, interner: interner)
        let sbType = types.make(.classType(ClassType(
            classSymbol: sbSymbol, args: [], nullability: .nonNull
        )))
        let stringType = types.stringType
        let intType = types.intType
        let nullableAnyType = types.makeNullable(types.anyType)
        let charType = types.make(.primitive(.char, .nonNull))

        // append(Any?): StringBuilder
        registerStringBuilderMemberFunction(
            named: "append",
            externalLinkName: "kk_string_builder_append_obj",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("value", nullableAnyType, false, false)],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // toString(): String
        registerStringBuilderMemberFunction(
            named: "toString",
            externalLinkName: "kk_string_builder_toString",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: stringType,
            symbols: symbols,
            interner: interner
        )

        // length: Int (property)
        registerStringBuilderMemberProperty(
            named: "length",
            externalLinkName: "kk_string_builder_length_prop",
            ownerSymbol: sbSymbol,
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        // appendLine(Any?): StringBuilder
        registerStringBuilderMemberFunction(
            named: "appendLine",
            externalLinkName: "kk_string_builder_appendLine_obj",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("value", nullableAnyType, false, false)],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // appendLine(): StringBuilder (no-arg overload)
        registerStringBuilderMemberFunction(
            named: "appendLine",
            externalLinkName: "kk_string_builder_appendLine_noarg_obj",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // insert(Int, Any?): StringBuilder
        registerStringBuilderMemberFunction(
            named: "insert",
            externalLinkName: "kk_string_builder_insert_obj",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("index", intType, false, false), ("value", nullableAnyType, false, false)],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // delete(Int, Int): StringBuilder
        registerStringBuilderMemberFunction(
            named: "delete",
            externalLinkName: "kk_string_builder_delete_obj",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("startIndex", intType, false, false), ("endIndex", intType, false, false)],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // clear(): StringBuilder
        registerStringBuilderMemberFunction(
            named: "clear",
            externalLinkName: "kk_string_builder_clear",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // reverse(): StringBuilder
        registerStringBuilderMemberFunction(
            named: "reverse",
            externalLinkName: "kk_string_builder_reverse",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // deleteCharAt(Int): StringBuilder
        registerStringBuilderMemberFunction(
            named: "deleteCharAt",
            externalLinkName: "kk_string_builder_deleteCharAt",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("index", intType, false, false)],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // get(Int): Char (operator)
        registerStringBuilderMemberFunction(
            named: "get",
            externalLinkName: "kk_string_builder_get",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("index", intType, false, false)],
            returnType: charType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Private Helpers

    private func ensureKotlinTextPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
        if symbols.lookup(fqName: kotlinTextPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("text"),
                fqName: kotlinTextPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return kotlinTextPkg
    }

    private func registerStringBuilderMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []

        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
            parameterDefaults.append(parameter.hasDefault)
            parameterVarargs.append(parameter.isVararg)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: parameterVarargs,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
    }

    private func registerStringBuilderMemberProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }
}
