import Foundation

/// Synthetic Kotlin/JS `Date` external class surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsDateStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let dateSymbol = ensureClassSymbol(
            named: "Date",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: dateSymbol)
        }
        let dateType = types.make(.classType(ClassType(
            classSymbol: dateSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(dateType, for: dateSymbol)

        let jsonSymbol = ensureInterfaceSymbol(
            named: "Json",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsonSymbol)
        }
        let jsonType = types.make(.classType(ClassType(
            classSymbol: jsonSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(jsonType, for: jsonSymbol)

        let dateFQName = kotlinJsPkg + [interner.intern("Date")]
        let localeOptionsSymbol = ensureInterfaceSymbol(
            named: "LocaleOptions",
            in: dateFQName,
            symbols: symbols,
            interner: interner
        )
        symbols.setParentSymbol(dateSymbol, for: localeOptionsSymbol)
        let localeOptionsType = types.make(.classType(ClassType(
            classSymbol: localeOptionsSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(localeOptionsType, for: localeOptionsSymbol)

        if let dateCompanionSymbol = registerJsDateCompanion(
            ownerSymbol: dateSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        ) {
            let dateCompanionType = types.make(.classType(ClassType(
                classSymbol: dateCompanionSymbol,
                args: [],
                nullability: .nonNull
            )))
            registerJsDateCompanionMember(
                ownerSymbol: dateCompanionSymbol,
                ownerType: dateCompanionType,
                named: "now",
                returnType: types.doubleType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }

        let arraySymbol = ensureClassSymbol(
            named: "Array",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let stringArrayType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(types.stringType)],
            nullability: .nonNull
        )))

        let numberType = types.anyType
        let intType = types.intType

        [
            [],
            [("milliseconds", numberType)],
            [("dateString", types.stringType)],
            [("year", intType), ("month", intType)],
            [("year", intType), ("month", intType), ("day", intType)],
            [("year", intType), ("month", intType), ("day", intType), ("hour", intType)],
            [
                ("year", intType),
                ("month", intType),
                ("day", intType),
                ("hour", intType),
                ("minute", intType),
            ],
            [
                ("year", intType),
                ("month", intType),
                ("day", intType),
                ("hour", intType),
                ("minute", intType),
                ("second", intType),
            ],
            [
                ("year", intType),
                ("month", intType),
                ("day", intType),
                ("hour", intType),
                ("minute", intType),
                ("second", intType),
                ("millisecond", numberType),
            ],
        ].forEach { parameters in
            registerJsDateConstructor(
                ownerSymbol: dateSymbol,
                ownerType: dateType,
                parameters: parameters,
                symbols: symbols,
                interner: interner
            )
        }

        for name in [
            "getDate",
            "getDay",
            "getFullYear",
            "getHours",
            "getMilliseconds",
            "getMinutes",
            "getMonth",
            "getSeconds",
            "getTimezoneOffset",
            "getUTCDate",
            "getUTCDay",
            "getUTCFullYear",
            "getUTCHours",
            "getUTCMilliseconds",
            "getUTCMinutes",
            "getUTCMonth",
            "getUTCSeconds",
        ] {
            registerJsDateMember(
                ownerSymbol: dateSymbol,
                ownerType: dateType,
                named: name,
                returnType: intType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }

        registerJsDateMember(
            ownerSymbol: dateSymbol,
            ownerType: dateType,
            named: "getTime",
            returnType: types.doubleType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        for name in [
            "toDateString",
            "toISOString",
            "toTimeString",
            "toUTCString",
        ] {
            registerJsDateMember(
                ownerSymbol: dateSymbol,
                ownerType: dateType,
                named: name,
                returnType: types.stringType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }

        registerJsDateMember(
            ownerSymbol: dateSymbol,
            ownerType: dateType,
            named: "toJSON",
            returnType: jsonType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        for name in ["toLocaleDateString", "toLocaleString", "toLocaleTimeString"] {
            registerJsDateMember(
                ownerSymbol: dateSymbol,
                ownerType: dateType,
                named: name,
                returnType: types.stringType,
                parameters: [
                    ("locales", stringArrayType, true),
                    ("options", localeOptionsType, true),
                ],
                symbols: symbols,
                interner: interner
            )
            registerJsDateMember(
                ownerSymbol: dateSymbol,
                ownerType: dateType,
                named: name,
                returnType: types.stringType,
                parameters: [
                    ("locales", types.stringType, false),
                    ("options", localeOptionsType, true),
                ],
                symbols: symbols,
                interner: interner
            )
        }

        for name in [
            "day",
            "era",
            "formatMatcher",
            "hour",
            "localeMatcher",
            "minute",
            "month",
            "second",
            "timeZone",
            "timeZoneName",
            "weekday",
            "year",
        ] {
            registerJsDateLocaleOptionProperty(
                ownerSymbol: localeOptionsSymbol,
                named: name,
                propertyType: types.makeNullable(types.stringType),
                symbols: symbols,
                interner: interner
            )
        }
        registerJsDateLocaleOptionProperty(
            ownerSymbol: localeOptionsSymbol,
            named: "hour12",
            propertyType: types.makeNullable(types.booleanType),
            symbols: symbols,
            interner: interner
        )
    }

    private func registerJsDateCompanion(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID? {
        if let existingCompanion = symbols.companionObjectSymbol(for: ownerSymbol),
           let companionInfo = symbols.symbol(existingCompanion)
        {
            let companionType = types.make(.classType(ClassType(
                classSymbol: companionInfo.id,
                args: [],
                nullability: .nonNull
            )))
            symbols.setPropertyType(companionType, for: companionInfo.id)
            return companionInfo.id
        }
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return nil }
        let companionName = interner.intern("Companion")
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
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(companionType, for: companionSymbol)
        return companionSymbol
    }

    private func registerJsDateConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let parameterTypes = parameters.map(\.type)
        let alreadyRegistered = symbols.lookupAll(fqName: ctorFQName).contains { symbol in
            symbols.functionSignature(for: symbol)?.parameterTypes == parameterTypes
        }
        guard !alreadyRegistered else { return }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerJsDateMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        named name: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        let parameterTypes = parameters.map(\.type)
        let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
        }
        guard !alreadyRegistered else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameters.map(\.hasDefault),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: memberSymbol
        )
    }

    private func registerJsDateCompanionMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        named name: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        let parameterTypes = parameters.map(\.type)
        let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
        }
        guard !alreadyRegistered else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameters.map(\.hasDefault),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: memberSymbol
        )
    }

    private func registerJsDateLocaleOptionProperty(
        ownerSymbol: SymbolID,
        named name: String,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else {
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
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }
}
