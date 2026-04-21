/// Synthetic stubs for kotlin.time.Duration class, Companion extension properties,
/// and inWhole* accessor properties (STDLIB-582/583/584).
extension DataFlowSemaPhase {
    func registerSyntheticDurationStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensureDurationPackageHierarchy(
            symbols: symbols,
            interner: interner
        )

        // --- Duration class symbol ---
        let durationSymbol = ensureClassSymbol(
            named: "Duration",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let durationCompanionFQName = ensureDurationCompanionSymbol(
            ownerSymbol: durationSymbol,
            symbols: symbols,
            interner: interner
        )
        guard let durationCompanionSymbol = symbols.companionObjectSymbol(for: durationSymbol) else {
            return
        }
        let durationType = types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let intType = types.intType
        let longType = types.longType
        let doubleType = types.doubleType
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // --- STDLIB-TIME-STABLE-001: Duration companion constants ---
        registerDurationMemberProperty(
            named: "ZERO",
            externalLinkName: "kk_duration_zero",
            ownerSymbol: durationCompanionSymbol,
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "INFINITE",
            externalLinkName: "kk_duration_infinite",
            ownerSymbol: durationCompanionSymbol,
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-582/583/584: Duration.inWhole* properties ---
        registerDurationMemberProperty(
            named: "inWholeMilliseconds",
            externalLinkName: "kk_duration_inWholeMilliseconds",
            ownerSymbol: durationSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "inWholeSeconds",
            externalLinkName: "kk_duration_inWholeSeconds",
            ownerSymbol: durationSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "inWholeMinutes",
            externalLinkName: "kk_duration_inWholeMinutes",
            ownerSymbol: durationSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "inWholeMicroseconds",
            externalLinkName: "kk_duration_inWholeMicroseconds",
            ownerSymbol: durationSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "inWholeNanoseconds",
            externalLinkName: "kk_duration_inWholeNanoseconds",
            ownerSymbol: durationSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "inWholeHours",
            externalLinkName: "kk_duration_inWholeHours",
            ownerSymbol: durationSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "inWholeDays",
            externalLinkName: "kk_duration_inWholeDays",
            ownerSymbol: durationSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TIME-082: Duration advanced properties ---
        registerDurationMemberProperty(
            named: "absoluteValue",
            externalLinkName: "kk_duration_absoluteValue",
            ownerSymbol: durationSymbol,
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "isNegative",
            externalLinkName: "kk_duration_isNegative",
            ownerSymbol: durationSymbol,
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "isPositive",
            externalLinkName: "kk_duration_isPositive",
            ownerSymbol: durationSymbol,
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "isInfinite",
            externalLinkName: "kk_duration_isInfinite",
            ownerSymbol: durationSymbol,
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberProperty(
            named: "isFinite",
            externalLinkName: "kk_duration_isFinite",
            ownerSymbol: durationSymbol,
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TIME-082: Duration member methods ---
        registerDurationMemberMethod(
            named: "plus",
            externalLinkName: "kk_duration_plus",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [durationType],
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "minus",
            externalLinkName: "kk_duration_minus",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [durationType],
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "times",
            externalLinkName: "kk_duration_times_int",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [intType],
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "div",
            externalLinkName: "kk_duration_div_int",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [intType],
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "div",
            externalLinkName: "kk_duration_div_duration",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [durationType],
            returnType: doubleType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "compareTo",
            externalLinkName: "kk_duration_compareTo",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [durationType],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "unaryMinus",
            externalLinkName: "kk_duration_unary_minus",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [],
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        // --- Duration.Companion extension properties (Int.seconds, Int.milliseconds, etc.) ---
        // These are extension properties on Int that return Duration.
        // Kotlin: val Int.seconds: Duration  (extension on Duration.Companion)
        // We register them as extension properties on Int with external link names.

        registerDurationFactoryExtensionProperty(
            named: "seconds",
            externalLinkName: "kk_duration_from_seconds",
            receiverType: intType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "milliseconds",
            externalLinkName: "kk_duration_from_milliseconds",
            receiverType: intType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "minutes",
            externalLinkName: "kk_duration_from_minutes",
            receiverType: intType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "nanoseconds",
            externalLinkName: "kk_duration_from_nanoseconds",
            receiverType: intType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "microseconds",
            externalLinkName: "kk_duration_from_microseconds",
            receiverType: intType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "hours",
            externalLinkName: "kk_duration_from_hours",
            receiverType: intType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "days",
            externalLinkName: "kk_duration_from_days",
            receiverType: intType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-660: TimedValue class ---
        let timedValueSymbol = ensureClassSymbol(
            named: "TimedValue",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        // TimedValue.value property (returns Any? — generic T erased to Any?)
        registerDurationMemberProperty(
            named: "value",
            externalLinkName: "kk_timedvalue_value",
            ownerSymbol: timedValueSymbol,
            returnType: types.makeNullable(types.anyType),
            symbols: symbols,
            interner: interner
        )

        // TimedValue.duration property (returns Duration)
        registerDurationMemberProperty(
            named: "duration",
            externalLinkName: "kk_timedvalue_duration",
            ownerSymbol: timedValueSymbol,
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-663: Long receiver Duration factory extension properties ---
        // Kotlin: val Long.seconds: Duration  (extension on Duration.Companion)

        registerDurationFactoryExtensionProperty(
            named: "seconds",
            externalLinkName: "kk_duration_from_seconds_long",
            receiverType: longType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "milliseconds",
            externalLinkName: "kk_duration_from_milliseconds_long",
            receiverType: longType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "minutes",
            externalLinkName: "kk_duration_from_minutes_long",
            receiverType: longType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "nanoseconds",
            externalLinkName: "kk_duration_from_nanoseconds_long",
            receiverType: longType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "microseconds",
            externalLinkName: "kk_duration_from_microseconds_long",
            receiverType: longType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "hours",
            externalLinkName: "kk_duration_from_hours_long",
            receiverType: longType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "days",
            externalLinkName: "kk_duration_from_days_long",
            receiverType: longType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TIME-STABLE-005: Double receiver Duration factory extension properties ---
        registerDurationFactoryExtensionProperty(
            named: "seconds",
            externalLinkName: "kk_duration_from_seconds_double",
            receiverType: doubleType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "milliseconds",
            externalLinkName: "kk_duration_from_milliseconds_double",
            receiverType: doubleType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "microseconds",
            externalLinkName: "kk_duration_from_microseconds_double",
            receiverType: doubleType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "nanoseconds",
            externalLinkName: "kk_duration_from_nanoseconds_double",
            receiverType: doubleType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "minutes",
            externalLinkName: "kk_duration_from_minutes_double",
            receiverType: doubleType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "hours",
            externalLinkName: "kk_duration_from_hours_double",
            receiverType: doubleType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "days",
            externalLinkName: "kk_duration_from_days_double",
            receiverType: doubleType,
            returnType: durationType,
            companionFQName: durationCompanionFQName,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureDurationCompanionSymbol(
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

    // MARK: - Duration Helpers

    private func ensureDurationPackageHierarchy(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinName = interner.intern("kotlin")
        let timeName = interner.intern("time")
        let kotlinFQ: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQ) == nil {
            _ = symbols.define(
                kind: .package, name: kotlinName, fqName: kotlinFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinTimeFQ: [InternedString] = [kotlinName, timeName]
        if symbols.lookup(fqName: kotlinTimeFQ) == nil {
            _ = symbols.define(
                kind: .package, name: timeName, fqName: kotlinTimeFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinTimeFQ
    }

    // MARK: - Duration member method registration (STDLIB-TIME-082)

    private func registerDurationMemberMethod(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]

        // Check for existing registration with matching parameter types
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .function,
                  let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if let existingSignature = symbols.functionSignature(for: existing),
               existingSignature.receiverType != ownerType
            {
                symbols.setFunctionSignature(
                    existingSignature.withReceiverType(ownerType),
                    for: existing
                )
            }
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        // Build parameter symbols
        var paramSymbols: [SymbolID] = []
        var paramDefaults: [Bool] = []
        var paramVarargs: [Bool] = []
        for (idx, paramType) in parameterTypes.enumerated() {
            let paramName = interner.intern("p\(idx)")
            let paramFQName = functionFQName + [paramName]
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: paramFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            symbols.setPropertyType(paramType, for: paramSymbol)
            paramSymbols.append(paramSymbol)
            paramDefaults.append(false)
            paramVarargs.append(false)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: paramDefaults,
                valueParameterIsVararg: paramVarargs,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
    }

    private func registerDurationMemberProperty(
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

    private func registerDurationFactoryExtensionProperty(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        returnType: TypeID,
        companionFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = companionFQName + [propertyName]

        // Check if already registered
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            // Also refresh the getter accessor's signature and external link name.
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
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)

        // Register getter accessor
        let getterSymbol = symbols.define(
            kind: .function,
            name: interner.intern("get"),
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: getterSymbol
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
    }
}

private extension FunctionSignature {
    func withReceiverType(_ receiverType: TypeID?) -> FunctionSignature {
        FunctionSignature(
            receiverType: receiverType,
            parameterTypes: parameterTypes,
            returnType: returnType,
            isSuspend: isSuspend,
            canThrow: canThrow,
            valueParameterSymbols: valueParameterSymbols,
            valueParameterHasDefaultValues: valueParameterHasDefaultValues,
            valueParameterIsVararg: valueParameterIsVararg,
            typeParameterSymbols: typeParameterSymbols,
            reifiedTypeParameterIndices: reifiedTypeParameterIndices,
            typeParameterUpperBounds: typeParameterUpperBounds,
            typeParameterUpperBoundsList: typeParameterUpperBoundsList,
            classTypeParameterCount: classTypeParameterCount
        )
    }
}
