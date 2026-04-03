/// Synthetic stubs for kotlin.time.Instant and kotlin.time.Clock (STDLIB-TIME-083/086).
///
/// Registers:
/// - `kotlin.time.Instant` class with:
///   - Companion factory methods: `now()`, `fromEpochMilliseconds(Long)`
///   - Instance properties: `epochSeconds`, `nanoOfSecond`
///   - Instance methods: `plus(Duration)`, `minus(Duration)`, `until(Instant)`, `elapsed()`
///   - Comparison via `compareTo(Instant)`
/// - `kotlin.time.Clock` interface with:
///   - `Clock.System` singleton object with `now()` method
///   - Instance method `now()` on the Clock interface
extension DataFlowSemaPhase {
    func registerSyntheticClockStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensurePackage(
            path: ["kotlin", "time"],
            symbols: symbols,
            interner: interner
        )

        // --- Locate Duration type (needed for method signatures) ---
        let durationFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("Duration"),
        ]
        let durationSymbolOpt = symbols.lookup(fqName: durationFQName)
        let durationType: TypeID
        if let durationSym = durationSymbolOpt {
            durationType = types.make(.classType(ClassType(
                classSymbol: durationSym,
                args: [],
                nullability: .nonNull
            )))
        } else {
            durationType = types.anyType
        }

        // MARK: - Instant class

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

        let longType = types.longType
        let intType = types.intType

        // --- Instant.Companion factory methods ---

        let instantCompanionFQName = ensureClockCompanionSymbol(
            named: "Companion",
            ownerSymbol: instantSymbol,
            symbols: symbols,
            interner: interner
        )

        // Instant.now() -> Instant
        registerClockCompanionMethod(
            named: "now",
            externalLinkName: "kk_instant_now",
            returnType: instantType,
            parameters: [],
            companionFQName: instantCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        // Instant.fromEpochMilliseconds(Long) -> Instant
        registerClockCompanionMethod(
            named: "fromEpochMilliseconds",
            externalLinkName: "kk_instant_from_epoch_millis",
            returnType: instantType,
            parameters: [(name: "epochMilliseconds", type: longType)],
            companionFQName: instantCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- Instant instance properties ---

        // epochSeconds: Long
        registerClockMemberProperty(
            named: "epochSeconds",
            externalLinkName: "kk_instant_epoch_seconds",
            ownerSymbol: instantSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        // nanoOfSecond: Int
        registerClockMemberProperty(
            named: "nanoOfSecond",
            externalLinkName: "kk_instant_nano_of_second",
            ownerSymbol: instantSymbol,
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        // --- Instant instance methods ---

        // plus(duration: Duration): Instant  [operator fun]
        registerClockMemberFunction(
            named: "plus",
            externalLinkName: "kk_instant_plus_duration",
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            parameters: [(name: "duration", type: durationType)],
            returnType: instantType,
            symbols: symbols,
            interner: interner,
            isOperator: true
        )

        // minus(duration: Duration): Instant  [operator fun]
        registerClockMemberFunction(
            named: "minus",
            externalLinkName: "kk_instant_minus_duration",
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            parameters: [(name: "duration", type: durationType)],
            returnType: instantType,
            symbols: symbols,
            interner: interner,
            isOperator: true
        )

        // until(other: Instant): Duration
        registerClockMemberFunction(
            named: "until",
            externalLinkName: "kk_instant_until",
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            parameters: [(name: "other", type: instantType)],
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        // elapsed(): Duration
        registerClockMemberFunction(
            named: "elapsed",
            externalLinkName: "kk_instant_elapsed",
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            parameters: [],
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )

        // compareTo(other: Instant): Int  [operator fun]
        registerClockMemberFunction(
            named: "compareTo",
            externalLinkName: "kk_instant_compare",
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            parameters: [(name: "other", type: instantType)],
            returnType: intType,
            symbols: symbols,
            interner: interner,
            isOperator: true
        )

        // MARK: - Clock interface

        let clockSymbol = ensureClassSymbol(
            named: "Clock",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let clockType = types.make(.classType(ClassType(
            classSymbol: clockSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Clock.now() -> Instant (interface method)
        registerClockMemberFunction(
            named: "now",
            externalLinkName: "kk_clock_now",
            ownerSymbol: clockSymbol,
            ownerType: clockType,
            parameters: [],
            returnType: instantType,
            symbols: symbols,
            interner: interner
        )

        // --- Clock.System nested object ---

        let clockSystemFQName = ensureClockNestedObject(
            named: "System",
            ownerSymbol: clockSymbol,
            ownerFQName: kotlinTimePkg + [interner.intern("Clock")],
            symbols: symbols,
            interner: interner
        )

        // Retrieve the System symbol so we can get its TypeID for
        // registerClockMemberFunction (which requires a receiverType).
        guard let clockSystemSymbol = symbols.lookup(fqName: clockSystemFQName) else { return }
        let clockSystemType = types.make(.classType(ClassType(
            classSymbol: clockSystemSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Clock.System.now() -> Instant
        // Registered as an instance member on the System object so that the
        // type checker can find it via collectMemberFunctionCandidates when the
        // receiver expression is typed as Clock.System (an object, not a class).
        registerClockMemberFunction(
            named: "now",
            externalLinkName: "kk_clock_system_now",
            ownerSymbol: clockSystemSymbol,
            ownerType: clockSystemType,
            parameters: [],
            returnType: instantType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Clock Helpers

    private func ensureClockCompanionSymbol(
        named companionName: String,
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
        let interned = interner.intern(companionName)
        let fqName = ownerInfo.fqName + [interned]
        let companionSymbol = symbols.define(
            kind: .object,
            name: interned,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
        return fqName
    }

    /// Creates a nested object (e.g. Clock.System) under an existing class symbol.
    /// Returns the FQ name of the newly created (or existing) object.
    private func ensureClockNestedObject(
        named objectName: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let interned = interner.intern(objectName)
        let fqName = ownerFQName + [interned]
        if let existing = symbols.lookup(fqName: fqName) {
            if let info = symbols.symbol(existing) {
                return info.fqName
            }
        }
        let objectSymbol = symbols.define(
            kind: .object,
            name: interned,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: objectSymbol)
        return fqName
    }

    private func registerClockCompanionMethod(
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

    private func registerClockMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        isOperator: Bool = false
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) == nil else {
            return
        }
        var flags: SymbolFlags = [.synthetic]
        if isOperator { flags.insert(.operatorFunction) }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        var parameterTypes: [TypeID] = []
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
            parameterTypes.append(parameter.type)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerClockMemberProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
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
