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
        let appendableSymbol = ensureInterfaceSymbol(
            named: "Appendable",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg) {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: appendableSymbol)
        }
        symbols.setDirectSupertypes([appendableSymbol], for: sbSymbol)
        types.setNominalDirectSupertypes([appendableSymbol], for: sbSymbol)
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let charSequenceSymbol = ensureInterfaceSymbol(
            named: "CharSequence",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let charSequenceType = types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol, args: [], nullability: .nonNull
        )))
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: charSequenceSymbol)
        }
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
            externalLinkName: "kk_string_builder_append_line_obj",
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
            externalLinkName: "kk_string_builder_append_line_noarg_obj",
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

        // deleteRange(Int, Int): StringBuilder (STDLIB-TEXT-BUILDER-002)
        registerStringBuilderMemberFunction(
            named: "deleteRange",
            externalLinkName: "kk_string_builder_deleteRange",
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

        // deleteAt(Int): StringBuilder (STDLIB-TEXT-BUILDER-001)
        registerStringBuilderMemberFunction(
            named: "deleteAt",
            externalLinkName: "kk_string_builder_deleteAt",
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

        // appendRange(CharSequence, Int, Int): StringBuilder (STDLIB-580)
        // The runtime still accepts raw string storage, but the surface type now
        // matches Kotlin's CharSequence signature.
        registerStringBuilderMemberFunction(
            named: "appendRange",
            externalLinkName: "kk_string_builder_appendRange_obj",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("value", charSequenceType, false, false), ("startIndex", intType, false, false), ("endIndex", intType, false, false)],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-STR-123: Additional StringBuilder methods

        // replace(Int, Int, String): StringBuilder
        registerStringBuilderMemberFunction(
            named: "replace",
            externalLinkName: "kk_string_builder_replace_obj",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("start", intType, false, false), ("end", intType, false, false), ("str", stringType, false, false)],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // setCharAt(Int, Char): Unit
        registerStringBuilderMemberFunction(
            named: "setCharAt",
            externalLinkName: "kk_string_builder_setCharAt",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("index", intType, false, false), ("value", charType, false, false)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // capacity(): Int
        registerStringBuilderMemberFunction(
            named: "capacity",
            externalLinkName: "kk_string_builder_capacity",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        // ensureCapacity(Int): Unit
        registerStringBuilderMemberFunction(
            named: "ensureCapacity",
            externalLinkName: "kk_string_builder_ensureCapacity",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("minimumCapacity", intType, false, false)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // trimToSize(): Unit
        registerStringBuilderMemberFunction(
            named: "trimToSize",
            externalLinkName: "kk_string_builder_trimToSize",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-TEXT-EDGE-012: append(vararg value: String?): StringBuilder
        registerStringBuilderMemberFunction(
            named: "append",
            externalLinkName: "kk_string_builder_append_vararg_obj",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("value", types.makeNullable(stringType), false, true)],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-TEXT-EDGE-012: append(vararg value: Any?): StringBuilder
        registerStringBuilderMemberFunction(
            named: "append",
            externalLinkName: "kk_string_builder_append_vararg_obj",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("value", nullableAnyType, false, true)],
            returnType: sbType,
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
