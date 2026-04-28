/// Synthetic stubs for kotlin.time experimental time APIs (STDLIB-TIME-180).
///
/// Registers:
/// - `@ExperimentalTime`
/// - `TimeSource` with nested `WithComparableMarks`, `Monotonic`, and `markNow()`
/// - `TimeMark` with elapsed/boolean checks and +/- Duration
/// - `ComparableTimeMark` with TimeMark operations plus mark-to-mark diff/comparison
/// - `AbstractDoubleTimeSource` / `AbstractLongTimeSource` surfaces
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
        let durationUnitSymbol = ensureClassSymbol(
            named: "DurationUnit",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let durationUnitType = types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
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

        let timeSourceSymbol = ensureInterfaceSymbol(
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

        let withComparableMarksFQName = ensureExperimentalTimeNestedInterface(
            named: "WithComparableMarks",
            ownerSymbol: timeSourceSymbol,
            ownerFQName: kotlinTimePkg + [interner.intern("TimeSource")],
            symbols: symbols,
            interner: interner
        )
        guard let withComparableMarksSymbol = symbols.lookup(fqName: withComparableMarksFQName) else {
            return
        }
        let withComparableMarksType = types.make(.classType(ClassType(
            classSymbol: withComparableMarksSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setDirectSupertypes([timeSourceSymbol], for: withComparableMarksSymbol)
        types.setNominalDirectSupertypes([timeSourceSymbol], for: withComparableMarksSymbol)
        registerExperimentalTimeMemberFunction(
            named: "markNow",
            externalLinkName: "kk_time_source_mark_now",
            ownerSymbol: withComparableMarksSymbol,
            ownerType: withComparableMarksType,
            parameters: [],
            returnType: comparableTimeMarkType,
            symbols: symbols,
            interner: interner,
            flags: [.synthetic, .abstractType, .overrideMember]
        )

        let abstractDoubleTimeSourceSymbol = ensureClassSymbol(
            named: "AbstractDoubleTimeSource",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.abstractType, .synthetic], for: abstractDoubleTimeSourceSymbol)
        symbols.setDirectSupertypes([withComparableMarksSymbol], for: abstractDoubleTimeSourceSymbol)
        types.setNominalDirectSupertypes([withComparableMarksSymbol], for: abstractDoubleTimeSourceSymbol)
        let abstractDoubleTimeSourceType = types.make(.classType(ClassType(
            classSymbol: abstractDoubleTimeSourceSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerExperimentalTimeConstructor(
            ownerSymbol: abstractDoubleTimeSourceSymbol,
            ownerType: abstractDoubleTimeSourceType,
            parameters: [(name: "unit", type: durationUnitType)],
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberProperty(
            named: "unit",
            ownerSymbol: abstractDoubleTimeSourceSymbol,
            returnType: durationUnitType,
            visibility: .protected,
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberFunction(
            named: "read",
            externalLinkName: nil,
            ownerSymbol: abstractDoubleTimeSourceSymbol,
            ownerType: abstractDoubleTimeSourceType,
            parameters: [],
            returnType: types.doubleType,
            symbols: symbols,
            interner: interner,
            visibility: .protected,
            flags: [.synthetic, .abstractType]
        )
        registerExperimentalTimeMemberFunction(
            named: "markNow",
            externalLinkName: "kk_time_source_mark_now",
            ownerSymbol: abstractDoubleTimeSourceSymbol,
            ownerType: abstractDoubleTimeSourceType,
            parameters: [],
            returnType: comparableTimeMarkType,
            symbols: symbols,
            interner: interner,
            flags: [.synthetic, .openType, .overrideMember]
        )

        let abstractLongTimeSourceSymbol = ensureClassSymbol(
            named: "AbstractLongTimeSource",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.abstractType, .synthetic], for: abstractLongTimeSourceSymbol)
        symbols.setDirectSupertypes([withComparableMarksSymbol], for: abstractLongTimeSourceSymbol)
        types.setNominalDirectSupertypes([withComparableMarksSymbol], for: abstractLongTimeSourceSymbol)
        let abstractLongTimeSourceType = types.make(.classType(ClassType(
            classSymbol: abstractLongTimeSourceSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerExperimentalTimeConstructor(
            ownerSymbol: abstractLongTimeSourceSymbol,
            ownerType: abstractLongTimeSourceType,
            parameters: [(name: "unit", type: durationUnitType)],
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberProperty(
            named: "unit",
            ownerSymbol: abstractLongTimeSourceSymbol,
            returnType: durationUnitType,
            visibility: .protected,
            symbols: symbols,
            interner: interner
        )
        registerExperimentalTimeMemberFunction(
            named: "read",
            externalLinkName: nil,
            ownerSymbol: abstractLongTimeSourceSymbol,
            ownerType: abstractLongTimeSourceType,
            parameters: [],
            returnType: types.longType,
            symbols: symbols,
            interner: interner,
            visibility: .protected,
            flags: [.synthetic, .abstractType]
        )
        registerExperimentalTimeMemberFunction(
            named: "markNow",
            externalLinkName: "kk_time_source_mark_now",
            ownerSymbol: abstractLongTimeSourceSymbol,
            ownerType: abstractLongTimeSourceType,
            parameters: [],
            returnType: comparableTimeMarkType,
            symbols: symbols,
            interner: interner,
            flags: [.synthetic, .openType, .overrideMember]
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
        symbols.setDirectSupertypes([withComparableMarksSymbol], for: monotonicSymbol)
        types.setNominalDirectSupertypes([withComparableMarksSymbol], for: monotonicSymbol)
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

    private func ensureExperimentalTimeNestedInterface(
        named interfaceName: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let interned = interner.intern(interfaceName)
        let fqName = ownerFQName + [interned]
        if let existing = symbols.lookup(fqName: fqName),
           let info = symbols.symbol(existing)
        {
            return info.fqName
        }
        let interfaceSymbol = symbols.define(
            kind: .interface,
            name: interned,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: interfaceSymbol)
        return fqName
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
        externalLinkName: String?,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        isOperator: Bool = false,
        visibility: Visibility = .public,
        flags explicitFlags: SymbolFlags? = nil
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
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            if let explicitFlags {
                symbols.insertFlags(explicitFlags, for: existing)
            }
            return
        }

        var flags: SymbolFlags = explicitFlags ?? [.synthetic]
        if isOperator {
            flags.insert(.operatorFunction)
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: visibility,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        }

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

    private func registerExperimentalTimeConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        let desiredParameterTypes = parameters.map { $0.type }
        if symbols.lookupAll(fqName: constructorFQName).contains(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == desiredParameterTypes
        }) {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: constructorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameter.type, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: desiredParameterTypes,
                returnType: ownerType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: constructorSymbol
        )
    }

    private func registerExperimentalTimeMemberProperty(
        named name: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        visibility: Visibility,
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
            symbols.setPropertyType(returnType, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: visibility,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }
}
