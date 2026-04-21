import Foundation

extension DataFlowSemaPhase {
    /// Register `kotlin.ranges.OpenEndRange<T>` so callers can type-check
    /// APIs that consume open-ended ranges.
    func registerSyntheticOpenEndRangeStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let rangesFQName = ensurePackage(
            path: ["kotlin", "ranges"],
            symbols: symbols,
            interner: interner
        )

        let openEndRangeSymbol = ensureInterfaceSymbol(
            named: "OpenEndRange",
            in: rangesFQName,
            symbols: symbols,
            interner: interner
        )

        let typeParamName = interner.intern("T")
        let typeParamFQName = rangesFQName + [interner.intern("OpenEndRange"), typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: openEndRangeSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: openEndRangeSymbol)

        if let comparableSymbol = types.comparableInterfaceSymbol {
            let comparableType = types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.in(typeParamType)],
                nullability: .nonNull
            )))
            symbols.setTypeParameterUpperBounds([comparableType], for: typeParamSymbol)
        }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: openEndRangeSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        registerOpenEndRangeProperty(
            named: "start",
            ownerSymbol: openEndRangeSymbol,
            ownerFQName: rangesFQName + [interner.intern("OpenEndRange")],
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerOpenEndRangeProperty(
            named: "endExclusive",
            ownerSymbol: openEndRangeSymbol,
            ownerFQName: rangesFQName + [interner.intern("OpenEndRange")],
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )

        registerOpenEndRangeFunction(
            named: "contains",
            ownerSymbol: openEndRangeSymbol,
            ownerFQName: rangesFQName + [interner.intern("OpenEndRange")],
            receiverType: receiverType,
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction],
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
        registerOpenEndRangeFunction(
            named: "isEmpty",
            ownerSymbol: openEndRangeSymbol,
            ownerFQName: rangesFQName + [interner.intern("OpenEndRange")],
            receiverType: receiverType,
            parameterTypes: [],
            returnType: types.booleanType,
            flags: [.synthetic],
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerOpenEndRangeProperty(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = ownerFQName + [propertyName]
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

    private func registerOpenEndRangeFunction(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        flags: SymbolFlags,
        typeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = ownerFQName + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: functionSymbol
        )
    }
}
