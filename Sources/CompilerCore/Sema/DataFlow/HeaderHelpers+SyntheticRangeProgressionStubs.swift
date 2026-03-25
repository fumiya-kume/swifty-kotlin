import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticRangeProgressionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinName = interner.intern("kotlin")
        let rangesName = interner.intern("ranges")
        let kotlinFQName: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQName) == nil {
            _ = symbols.define(
                kind: .package,
                name: kotlinName,
                fqName: kotlinFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let rangesFQName: [InternedString] = [kotlinName, rangesName]
        let rangesPackageSymbol: SymbolID
        if let existing = symbols.lookup(fqName: rangesFQName) {
            rangesPackageSymbol = existing
        } else {
            rangesPackageSymbol = symbols.define(
                kind: .package,
                name: rangesName,
                fqName: rangesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        registerSyntheticProgressionStub(
            named: "IntProgression",
            elementType: types.intType,
            stepType: types.intType,
            externalLinkName: "kk_int_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticProgressionStub(
            named: "LongProgression",
            elementType: types.longType,
            stepType: types.intType,
            externalLinkName: "kk_long_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticProgressionStub(
            named: "UIntProgression",
            elementType: types.uintType,
            stepType: types.intType,
            externalLinkName: "kk_uint_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticProgressionStub(
            named: "ULongProgression",
            elementType: types.ulongType,
            stepType: types.intType,
            externalLinkName: "kk_ulong_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticProgressionStub(
        named name: String,
        elementType: TypeID,
        stepType: TypeID,
        externalLinkName: String,
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = rangesFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            let created = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rangesPackageSymbol, for: created)
            classSymbol = created
        }

        let companionSymbol: SymbolID
        if let existing = symbols.companionObjectSymbol(for: classSymbol) {
            companionSymbol = existing
        } else {
            let companionName = interner.intern("Companion")
            let companionFQName = classFQName + [companionName]
            let created = symbols.define(
                kind: .object,
                name: companionName,
                fqName: companionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(classSymbol, for: created)
            symbols.setCompanionObjectSymbol(created, for: classSymbol)
            companionSymbol = created
        }

        guard let companionInfo = symbols.symbol(companionSymbol) else {
            return
        }
        let progressionType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionName = interner.intern("fromClosedRange")
        let functionFQName = companionInfo.fqName + [functionName]
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == companionType
                && signature.parameterTypes == [elementType, elementType, stepType]
        }) {
            return
        }

        let parameterNames = ["rangeStart", "rangeEnd", "step"].map(interner.intern)
        let parameterSymbols = parameterNames.map { parameterName in
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(companionSymbol, for: parameterSymbol)
            return parameterSymbol
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(companionSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: companionType,
                parameterTypes: [elementType, elementType, stepType],
                returnType: progressionType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: [false, false, false],
                valueParameterIsVararg: [false, false, false]
            ),
            for: functionSymbol
        )

        let listType = syntheticListType(elementType: elementType, symbols: symbols, types: types, interner: interner)
        let firstLastRuntime = name == "ULongProgression" ? ("kk_ulong_range_first", "kk_ulong_range_last") : ("kk_range_first", "kk_range_last")
        let stepRuntime = name == "ULongProgression" ? "kk_ulong_range_step" : "kk_range_step"
        let isEmptyRuntime = name == "ULongProgression" ? "kk_ulong_range_isEmpty" : "kk_range_isEmpty"
        let reversedRuntime: String
        let toListRuntime: String
        switch name {
        case "UIntProgression":
            reversedRuntime = "kk_uint_range_reversed"
            toListRuntime = "kk_uint_range_toList"
        case "ULongProgression":
            reversedRuntime = "kk_ulong_range_reversed"
            toListRuntime = "kk_ulong_range_toList"
        default:
            reversedRuntime = "kk_range_reversed"
            toListRuntime = "kk_range_toList"
        }

        registerProgressionProperty(
            named: "first",
            ownerSymbol: classSymbol,
            propertyType: elementType,
            externalLinkName: firstLastRuntime.0,
            symbols: symbols,
            interner: interner
        )
        registerProgressionProperty(
            named: "last",
            ownerSymbol: classSymbol,
            propertyType: elementType,
            externalLinkName: firstLastRuntime.1,
            symbols: symbols,
            interner: interner
        )
        registerProgressionProperty(
            named: "step",
            ownerSymbol: classSymbol,
            propertyType: stepType,
            externalLinkName: stepRuntime,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "toList",
            ownerSymbol: classSymbol,
            receiverType: progressionType,
            parameterTypes: [],
            returnType: listType,
            externalLinkName: toListRuntime,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "reversed",
            ownerSymbol: classSymbol,
            receiverType: progressionType,
            parameterTypes: [],
            returnType: progressionType,
            externalLinkName: reversedRuntime,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "isEmpty",
            ownerSymbol: classSymbol,
            receiverType: progressionType,
            parameterTypes: [],
            returnType: types.booleanType,
            externalLinkName: isEmptyRuntime,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "step",
            ownerSymbol: classSymbol,
            receiverType: progressionType,
            parameterTypes: [stepType],
            returnType: progressionType,
            externalLinkName: name == "ULongProgression" ? "kk_ulong_step" : (name == "UIntProgression" ? "kk_uint_step" : "kk_op_step"),
            symbols: symbols,
            interner: interner
        )
    }

    private func registerProgressionProperty(
        named name: String,
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if symbols.lookupAll(fqName: propertyFQName).contains(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }

    private func registerProgressionMethod(
        named name: String,
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
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

        let parameterSymbols = parameterTypes.enumerated().map { index, _ in
            let parameterName = interner.intern("p\(index)")
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ownerSymbol, for: parameterSymbol)
            return parameterSymbol
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
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func syntheticListType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard let listSymbol = symbols.lookupByShortName(interner.intern("List")).first else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }
}
