/// Synthetic stubs for kotlin.time experimental time APIs (STDLIB-TIME-180).
///
/// Registers:
/// - `@ExperimentalTime`
/// - `TimeSource` with nested `Monotonic` object and `markNow()`
/// - `TimeMark` with elapsed/boolean checks and +/- Duration
/// - `ComparableTimeMark` with TimeMark operations plus mark-to-mark diff/comparison
extension DataFlowSemaPhase {
    func registerSyntheticExperimentalTimeStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensurePackage(
            path: ["kotlin", "time"],
            symbols: symbols,
            interner: interner
        )

        _ = ensureAnnotationClassSymbol(
            named: "ExperimentalTime",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

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
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let intType = types.intType

        let timeMarkSymbol = ensureClassSymbol(
            named: "TimeMark",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let timeMarkType = types.make(.classType(ClassType(
            classSymbol: timeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))

        let comparableTimeMarkSymbol = ensureClassSymbol(
            named: "ComparableTimeMark",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let comparableTimeMarkType = types.make(.classType(ClassType(
            classSymbol: comparableTimeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))

        registerExperimentalTimeMemberFunction(
            named: "elapsedNow",
            externalLinkName: "kk_time_mark_elapsed_now",
            ownerSymbol: timeMarkSymbol,
            ownerType: timeMarkType,
            parameters: [],
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberFunction(
            named: "hasPassedNow",
            externalLinkName: "kk_time_mark_has_passed_now",
            ownerSymbol: timeMarkSymbol,
            ownerType: timeMarkType,
            parameters: [],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberFunction(
            named: "hasNotPassedNow",
            externalLinkName: "kk_time_mark_has_not_passed_now",
            ownerSymbol: timeMarkSymbol,
            ownerType: timeMarkType,
            parameters: [],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberFunction(
            named: "plus",
            externalLinkName: "kk_time_mark_plus_duration",
            ownerSymbol: timeMarkSymbol,
            ownerType: timeMarkType,
            parameters: [(name: "duration", type: durationType)],
            returnType: timeMarkType,
            symbols: symbols,
            interner: interner,
            isOperator: true
        )
        registerExperimentalTimeMemberFunction(
            named: "minus",
            externalLinkName: "kk_time_mark_minus_duration",
            ownerSymbol: timeMarkSymbol,
            ownerType: timeMarkType,
            parameters: [(name: "duration", type: durationType)],
            returnType: timeMarkType,
            symbols: symbols,
            interner: interner,
            isOperator: true
        )

        registerExperimentalTimeMemberFunction(
            named: "elapsedNow",
            externalLinkName: "kk_time_mark_elapsed_now",
            ownerSymbol: comparableTimeMarkSymbol,
            ownerType: comparableTimeMarkType,
            parameters: [],
            returnType: durationType,
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberFunction(
            named: "hasPassedNow",
            externalLinkName: "kk_time_mark_has_passed_now",
            ownerSymbol: comparableTimeMarkSymbol,
            ownerType: comparableTimeMarkType,
            parameters: [],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberFunction(
            named: "hasNotPassedNow",
            externalLinkName: "kk_time_mark_has_not_passed_now",
            ownerSymbol: comparableTimeMarkSymbol,
            ownerType: comparableTimeMarkType,
            parameters: [],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberFunction(
            named: "plus",
            externalLinkName: "kk_time_mark_plus_duration",
            ownerSymbol: comparableTimeMarkSymbol,
            ownerType: comparableTimeMarkType,
            parameters: [(name: "duration", type: durationType)],
            returnType: comparableTimeMarkType,
            symbols: symbols,
            interner: interner,
            isOperator: true
        )
        registerExperimentalTimeMemberFunction(
            named: "minus",
            externalLinkName: "kk_time_mark_minus_duration",
            ownerSymbol: comparableTimeMarkSymbol,
            ownerType: comparableTimeMarkType,
            parameters: [(name: "duration", type: durationType)],
            returnType: comparableTimeMarkType,
            symbols: symbols,
            interner: interner,
            isOperator: true
        )
        registerExperimentalTimeMemberFunction(
            named: "minus",
            externalLinkName: "kk_time_mark_minus_mark",
            ownerSymbol: comparableTimeMarkSymbol,
            ownerType: comparableTimeMarkType,
            parameters: [(name: "other", type: comparableTimeMarkType)],
            returnType: durationType,
            symbols: symbols,
            interner: interner,
            isOperator: true
        )
        registerExperimentalTimeMemberFunction(
            named: "compareTo",
            externalLinkName: "kk_time_mark_compare",
            ownerSymbol: comparableTimeMarkSymbol,
            ownerType: comparableTimeMarkType,
            parameters: [(name: "other", type: comparableTimeMarkType)],
            returnType: intType,
            symbols: symbols,
            interner: interner,
            isOperator: true
        )

        let timeSourceSymbol = ensureClassSymbol(
            named: "TimeSource",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let timeSourceType = types.make(.classType(ClassType(
            classSymbol: timeSourceSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerExperimentalTimeMemberFunction(
            named: "markNow",
            externalLinkName: "kk_time_source_mark_now",
            ownerSymbol: timeSourceSymbol,
            ownerType: timeSourceType,
            parameters: [],
            returnType: timeMarkType,
            symbols: symbols,
            interner: interner
        )

        let monotonicFQName = ensureExperimentalTimeNestedObject(
            named: "Monotonic",
            ownerSymbol: timeSourceSymbol,
            ownerFQName: kotlinTimePkg + [interner.intern("TimeSource")],
            symbols: symbols,
            interner: interner
        )
        guard let monotonicSymbol = symbols.lookup(fqName: monotonicFQName) else {
            return
        }
        let monotonicType = types.make(.classType(ClassType(
            classSymbol: monotonicSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerExperimentalTimeMemberFunction(
            named: "markNow",
            externalLinkName: "kk_time_source_monotonic_mark_now",
            ownerSymbol: monotonicSymbol,
            ownerType: monotonicType,
            parameters: [],
            returnType: comparableTimeMarkType,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureExperimentalTimeNestedObject(
        named objectName: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let interned = interner.intern(objectName)
        let fqName = ownerFQName + [interned]
        if let existing = symbols.lookup(fqName: fqName),
           let info = symbols.symbol(existing)
        {
            return info.fqName
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

    private func registerExperimentalTimeMemberFunction(
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
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        let desiredParameterTypes = parameters.map { $0.type }
        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == ownerType &&
                signature.parameterTypes == desiredParameterTypes &&
                signature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        var flags: SymbolFlags = [.synthetic]
        if isOperator {
            flags.insert(.operatorFunction)
        }
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
        for parameter in parameters {
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
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: desiredParameterTypes,
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
