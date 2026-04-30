/// Synthetic stubs for kotlin.time.Instant class (STDLIB-TIME-083).
/// Registers Instant.now(), Instant.fromEpochMilliseconds() companion factories,
/// instance properties (epochSeconds, nanoOfSecond), top-level extension
/// properties (isDistantPast, isDistantFuture), arithmetic operators
/// (+/-Duration), comparison (compareTo), until(), and elapsed().
extension DataFlowSemaPhase {
    func registerSyntheticInstantStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensurePackage(
            path: ["kotlin", "time"],
            symbols: symbols,
            interner: interner
        )

        // --- Instant class symbol ---
        let instantSymbol = ensureClassSymbol(
            named: "Instant",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        let instantType = types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Duration type for arithmetic
        let durationSymbol = ensureClassSymbol(
            named: "Duration",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let durationType = types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let longType = types.longType
        let intType = types.intType
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // --- Companion object for factory methods ---
        let companionFQName = ensureInstantCompanionSymbol(
            ownerSymbol: instantSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- Instant.now() companion factory ---
        registerInstantCompanionMethod(
            named: "now",
            externalLinkName: "kk_instant_now",
            returnType: instantType,
            parameters: [],
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- Instant.fromEpochMilliseconds(Long) companion factory ---
        registerInstantCompanionMethod(
            named: "fromEpochMilliseconds",
            externalLinkName: "kk_instant_from_epoch_millis",
            returnType: instantType,
            parameters: [(name: "epochMilliseconds", type: longType)],
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- epochSeconds property (Long) ---
        registerInstantMemberProperty(
            named: "epochSeconds",
            externalLinkName: "kk_instant_epoch_seconds",
            ownerSymbol: instantSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        // --- nanoOfSecond property (Int) ---
        registerInstantMemberProperty(
            named: "nanoOfSecond",
            externalLinkName: "kk_instant_nano_of_second",
            ownerSymbol: instantSymbol,
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        // --- top-level extension properties ---
        registerInstantExtensionProperty(
            named: "isDistantPast",
            packageFQName: kotlinTimePkg,
            receiverType: instantType,
            returnType: boolType,
            externalLinkName: "kk_instant_is_distant_past",
            symbols: symbols,
            interner: interner
        )
        registerInstantExtensionProperty(
            named: "isDistantFuture",
            packageFQName: kotlinTimePkg,
            receiverType: instantType,
            returnType: boolType,
            externalLinkName: "kk_instant_is_distant_future",
            symbols: symbols,
            interner: interner
        )

        // --- plus(Duration): Instant ---
        registerInstantInstanceMethod(
            named: "plus",
            externalLinkName: "kk_instant_plus_duration",
            returnType: instantType,
            parameters: [(name: "duration", type: durationType)],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            isOperator: true,
            symbols: symbols,
            interner: interner
        )

        // --- minus(Duration): Instant ---
        registerInstantInstanceMethod(
            named: "minus",
            externalLinkName: "kk_instant_minus_duration",
            returnType: instantType,
            parameters: [(name: "duration", type: durationType)],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            isOperator: true,
            symbols: symbols,
            interner: interner
        )

        // --- compareTo(Instant): Int ---
        registerInstantInstanceMethod(
            named: "compareTo",
            externalLinkName: "kk_instant_compare",
            returnType: intType,
            parameters: [(name: "other", type: instantType)],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            isOperator: true,
            symbols: symbols,
            interner: interner
        )

        // --- until(Instant): Duration ---
        registerInstantInstanceMethod(
            named: "until",
            externalLinkName: "kk_instant_until",
            returnType: durationType,
            parameters: [(name: "other", type: instantType)],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )

        // --- elapsed(): Duration ---
        registerInstantInstanceMethod(
            named: "elapsed",
            externalLinkName: "kk_instant_elapsed",
            returnType: durationType,
            parameters: [],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Instant Helpers

    private func ensureInstantCompanionSymbol(
        ownerSymbol: SymbolID,
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
        return companionFQName
    }

    private func registerInstantCompanionMethod(
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
            return existingSignature.parameterTypes == parameters.map { $0.type } &&
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
                parameterTypes: parameters.map { $0.type },
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerInstantMemberProperty(
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

    private func registerInstantExtensionProperty(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType
                    ),
                    for: getterSymbol
                )
                symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
            }
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)

        let getterSymbol = symbols.define(
            kind: .function,
            name: interner.intern("get"),
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: getterSymbol
        )
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
    }

    private func registerInstantInstanceMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        isOperator: Bool = false,
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
            return existingSignature.parameterTypes == parameters.map { $0.type } &&
                existingSignature.returnType == returnType
        }) == nil else {
            return
        }
        let memberFlags: SymbolFlags = isOperator ? [.synthetic, .operatorFunction] : [.synthetic]
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: memberFlags
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
                parameterTypes: parameters.map { $0.type },
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
