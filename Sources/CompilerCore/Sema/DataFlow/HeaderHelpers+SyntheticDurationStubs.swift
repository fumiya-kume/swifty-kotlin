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
        let durationType = types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let intType = types.intType
        let longType = types.longType

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

        // --- Duration.Companion extension properties (Int.seconds, Int.milliseconds, etc.) ---
        // These are extension properties on Int that return Duration.
        // Kotlin: val Int.seconds: Duration  (extension on Duration.Companion)
        // We register them as extension properties on Int with external link names.

        registerDurationFactoryExtensionProperty(
            named: "seconds",
            externalLinkName: "kk_duration_from_seconds",
            receiverType: intType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "milliseconds",
            externalLinkName: "kk_duration_from_milliseconds",
            receiverType: intType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "minutes",
            externalLinkName: "kk_duration_from_minutes",
            receiverType: intType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "nanoseconds",
            externalLinkName: "kk_duration_from_nanoseconds",
            receiverType: intType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "microseconds",
            externalLinkName: "kk_duration_from_microseconds",
            receiverType: intType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "hours",
            externalLinkName: "kk_duration_from_hours",
            receiverType: intType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
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
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "milliseconds",
            externalLinkName: "kk_duration_from_milliseconds_long",
            receiverType: longType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "minutes",
            externalLinkName: "kk_duration_from_minutes_long",
            receiverType: longType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "nanoseconds",
            externalLinkName: "kk_duration_from_nanoseconds_long",
            receiverType: longType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "microseconds",
            externalLinkName: "kk_duration_from_microseconds_long",
            receiverType: longType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionProperty(
            named: "hours",
            externalLinkName: "kk_duration_from_hours_long",
            receiverType: longType,
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
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
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]

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
