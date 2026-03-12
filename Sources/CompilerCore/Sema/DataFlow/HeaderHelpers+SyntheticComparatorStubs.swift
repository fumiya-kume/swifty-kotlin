import Foundation

/// Synthetic stubs for Comparator, compareBy, compareByDescending (STDLIB-175),
/// thenBy, thenByDescending, reversed (STDLIB-176), naturalOrder, reverseOrder (STDLIB-177).
extension DataFlowSemaPhase {
    func registerSyntheticComparatorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let comparisonsPkg: [InternedString] = kotlinPkg + [interner.intern("comparisons")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        let comparisonsPackageSymbol = ensureSyntheticPackage(fqName: comparisonsPkg, symbols: symbols)

        let comparatorSymbol = registerComparatorInterface(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinPkg: kotlinPkg
        )

        registerCompareByAndDescending(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )

        registerThenByAndReversed(
            symbols: symbols,
            types: types,
            interner: interner,
            comparatorSymbol: comparatorSymbol
        )

        registerNaturalAndReverseOrder(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )
    }

    private func ensureSyntheticPackage(
        fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID {
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        guard let name = fqName.last else {
            return .invalid
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func registerComparatorInterface(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) -> SymbolID {
        let comparatorName = interner.intern("Comparator")
        let comparatorFQName = kotlinPkg + [comparatorName]
        let comparatorSymbol: SymbolID = if let existing = symbols.lookup(fqName: comparatorFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: comparatorName,
                fqName: comparatorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .funInterface]
            )
        }

        // Define type parameter T for Comparator<T>
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        let tParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: tParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))

        // compare(a: T, b: T): Int
        let compareName = interner.intern("compare")
        let compareFQName = comparatorFQName + [compareName]
        guard symbols.lookup(fqName: compareFQName) == nil else {
            return comparatorSymbol
        }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let aName = interner.intern("a")
        let bName = interner.intern("b")
        let aSymbol = symbols.define(
            kind: .valueParameter,
            name: aName,
            fqName: compareFQName + [aName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let bSymbol = symbols.define(
            kind: .valueParameter,
            name: bName,
            fqName: compareFQName + [bName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let compareSymbol = symbols.define(
            kind: .function,
            name: compareName,
            fqName: compareFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .abstractType]
        )
        symbols.setParentSymbol(comparatorSymbol, for: compareSymbol)
        symbols.setParentSymbol(compareSymbol, for: aSymbol)
        symbols.setParentSymbol(compareSymbol, for: bSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [tParamType, tParamType],
                returnType: types.intType,
                typeParameterSymbols: [tParamSymbol],
                classTypeParameterCount: 1
            ),
            for: compareSymbol
        )

        return comparatorSymbol
    }

    private func registerCompareByAndDescending(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let comparatorFQName = symbols.symbol(comparatorSymbol)?.fqName ?? comparisonsPkg
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else { return }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))

        let comparatorType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let selectorType = types.make(.functionType(FunctionType(
            params: [tParamType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        for (name, extLink) in [
            ("compareBy", "kk_comparator_from_selector"),
            ("compareByDescending", "kk_comparator_from_selector_descending"),
        ] {
            let functionName = interner.intern(name)
            let functionFQName = comparisonsPkg + [functionName]
            if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == [selectorType] && sig.returnType == comparatorType
            }) {
                if let existing = symbols.lookupAll(fqName: functionFQName).first {
                    symbols.setExternalLinkName(extLink, for: existing)
                }
                continue
            }

            let funcSymbol = symbols.define(
                kind: .function,
                name: functionName,
                fqName: functionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
            symbols.setExternalLinkName(extLink, for: funcSymbol)

            let selectorParamName = interner.intern("selector")
            let selectorParamSymbol = symbols.define(
                kind: .valueParameter,
                name: selectorParamName,
                fqName: functionFQName + [selectorParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(funcSymbol, for: selectorParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [selectorType],
                    returnType: comparatorType,
                    isSuspend: false,
                    valueParameterSymbols: [selectorParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [tParamSymbol],
                    typeParameterUpperBoundsList: [[]]
                ),
                for: funcSymbol
            )
        }
    }

    private func registerThenByAndReversed(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparatorSymbol: SymbolID
    ) {
        guard let compInfo = symbols.symbol(comparatorSymbol) else { return }
        let comparatorFQName = compInfo.fqName
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else { return }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let selectorType = types.make(.functionType(FunctionType(
            params: [tParamType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        for (name, extLink) in [
            ("thenBy", "kk_comparator_then_by"),
            ("thenByDescending", "kk_comparator_then_by_descending"),
        ] {
            let memberName = interner.intern(name)
            let memberFQName = comparatorFQName + [memberName]
            if symbols.lookup(fqName: memberFQName) != nil { continue }

            let selectorParamName = interner.intern("selector")
            let selectorParamSymbol = symbols.define(
                kind: .valueParameter,
                name: selectorParamName,
                fqName: memberFQName + [selectorParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(comparatorSymbol, for: memberSymbol)
            symbols.setParentSymbol(memberSymbol, for: selectorParamSymbol)
            symbols.setExternalLinkName(extLink, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [selectorType],
                    returnType: receiverType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        let reversedName = interner.intern("reversed")
        let reversedFQName = comparatorFQName + [reversedName]
        if symbols.lookup(fqName: reversedFQName) == nil {
            let memberSymbol = symbols.define(
                kind: .function,
                name: reversedName,
                fqName: reversedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(comparatorSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_comparator_reversed", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: receiverType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }

    private func registerNaturalAndReverseOrder(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        guard let compInfo = symbols.symbol(comparatorSymbol) else { return }
        let comparatorFQName = compInfo.fqName
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else { return }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))
        let comparatorType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))

        for (name, extLink) in [
            ("naturalOrder", "kk_comparator_natural_order"),
            ("reverseOrder", "kk_comparator_reverse_order"),
        ] {
            let functionName = interner.intern(name)
            let functionFQName = comparisonsPkg + [functionName]
            if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes.isEmpty && sig.returnType == comparatorType
            }) {
                if let existing = symbols.lookupAll(fqName: functionFQName).first {
                    symbols.setExternalLinkName(extLink, for: existing)
                }
                continue
            }

            let funcSymbol = symbols.define(
                kind: .function,
                name: functionName,
                fqName: functionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
            symbols.setExternalLinkName(extLink, for: funcSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [],
                    returnType: comparatorType,
                    isSuspend: false,
                    typeParameterSymbols: [tParamSymbol],
                    typeParameterUpperBoundsList: [[]]
                ),
                for: funcSymbol
            )
        }
    }
}
