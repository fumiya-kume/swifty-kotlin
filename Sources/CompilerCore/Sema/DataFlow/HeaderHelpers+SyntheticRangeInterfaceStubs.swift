import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticRangeInterfaceStubs(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
        }
        guard let comparableSymbol = types.comparableInterfaceSymbol else {
            return
        }

        let closedRangeSymbol = registerSyntheticClosedRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            comparableSymbol: comparableSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticClosedFloatingPointRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            comparableSymbol: comparableSymbol,
            closedRangeSymbol: closedRangeSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticClosedRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        comparableSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let interfaceName = interner.intern("ClosedRange")
        let interfaceFQName = rangesFQName + [interfaceName]
        let interfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: interfaceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: interfaceName,
                fqName: interfaceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(rangesPackageSymbol, for: interfaceSymbol)

        let typeParamName = interner.intern("T")
        let typeParamFQName = interfaceFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: interfaceSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setTypeParameterUpperBounds(
            [comparableBoundType(
                comparableSymbol: comparableSymbol,
                elementType: typeParamType,
                types: types
            )],
            for: typeParamSymbol
        )

        registerRangeInterfaceProperty(
            named: "start",
            ownerSymbol: interfaceSymbol,
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerRangeInterfaceProperty(
            named: "endInclusive",
            ownerSymbol: interfaceSymbol,
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerRangeInterfaceFunction(
            named: "contains",
            ownerSymbol: interfaceSymbol,
            receiverType: interfaceType,
            parameterTypes: [typeParamType],
            parameterNames: ["value"],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerRangeInterfaceFunction(
            named: "isEmpty",
            ownerSymbol: interfaceSymbol,
            receiverType: interfaceType,
            parameterTypes: [],
            parameterNames: [],
            returnType: types.booleanType,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            types: types,
            interner: interner
        )

        return interfaceSymbol
    }

    private func registerSyntheticClosedFloatingPointRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        comparableSymbol: SymbolID,
        closedRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let interfaceName = interner.intern("ClosedFloatingPointRange")
        let interfaceFQName = rangesFQName + [interfaceName]
        let interfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: interfaceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: interfaceName,
                fqName: interfaceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(rangesPackageSymbol, for: interfaceSymbol)
        symbols.setDirectSupertypes([closedRangeSymbol], for: interfaceSymbol)
        types.setNominalDirectSupertypes([closedRangeSymbol], for: interfaceSymbol)

        let typeParamName = interner.intern("T")
        let typeParamFQName = interfaceFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: interfaceSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: interfaceSymbol, supertype: closedRangeSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(typeParamType)], for: interfaceSymbol, supertype: closedRangeSymbol)
        symbols.setTypeParameterUpperBounds(
            [comparableBoundType(
                comparableSymbol: comparableSymbol,
                elementType: typeParamType,
                types: types
            )],
            for: typeParamSymbol
        )

        registerRangeInterfaceProperty(
            named: "start",
            ownerSymbol: interfaceSymbol,
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerRangeInterfaceProperty(
            named: "endInclusive",
            ownerSymbol: interfaceSymbol,
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerRangeInterfaceFunction(
            named: "contains",
            ownerSymbol: interfaceSymbol,
            receiverType: interfaceType,
            parameterTypes: [typeParamType],
            parameterNames: ["value"],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerRangeInterfaceFunction(
            named: "isEmpty",
            ownerSymbol: interfaceSymbol,
            receiverType: interfaceType,
            parameterTypes: [],
            parameterNames: [],
            returnType: types.booleanType,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerRangeInterfaceFunction(
            named: "lessThanOrEquals",
            ownerSymbol: interfaceSymbol,
            receiverType: interfaceType,
            parameterTypes: [typeParamType, typeParamType],
            parameterNames: ["a", "b"],
            returnType: types.booleanType,
            flags: [.synthetic, .abstractType],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerRangeInterfaceProperty(
        named name: String,
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
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

    private func registerRangeInterfaceFunction(
        named name: String,
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameterTypes: [TypeID],
        parameterNames: [String],
        returnType: TypeID,
        flags: SymbolFlags = [.synthetic],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
        }) {
            return
        }

        let parameterSymbols = zip(parameterNames, parameterTypes).map { parameterName, _ in
            let internedName = interner.intern(parameterName)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: internedName,
                fqName: functionFQName + [internedName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            return parameterSymbol
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
        for parameterSymbol in parameterSymbols {
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: functionSymbol
        )
        symbols.setPropertyType(
            types.make(.functionType(FunctionType(
                params: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                nullability: .nonNull
            ))),
            for: functionSymbol
        )
    }

    private func comparableBoundType(
        comparableSymbol: SymbolID,
        elementType: TypeID,
        types: TypeSystem
    ) -> TypeID {
        types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(elementType)],
            nullability: .nonNull
        )))
    }
}
