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

        registerCompareByMultiSelector(
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

        registerNullsComparators(
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

        registerCompareValuesAndCompareValuesBy(
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

    /// Register compareBy overloads that take 2 or 3 selectors (STDLIB-613).
    private func registerCompareByMultiSelector(
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

        let functionName = interner.intern("compareBy")
        let functionFQName = comparisonsPkg + [functionName]

        // Register 2-selector and 3-selector overloads
        for arity in 2...3 {
            let paramTypes = Array(repeating: selectorType, count: arity)

            // Check if this overload already exists
            let extLink = arity == 2 ? "kk_comparator_from_multi_selectors" : "kk_comparator_from_multi_selectors3"
            if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == paramTypes && sig.returnType == comparatorType
            }) {
                if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                    guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                    return sig.parameterTypes == paramTypes && sig.returnType == comparatorType
                }) {
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

            var paramSymbols: [SymbolID] = []
            for i in 0..<arity {
                let paramName = interner.intern("selector\(i + 1)")
                // Use arity-qualified fqName to avoid collisions across overloads
                let paramInternalName = interner.intern("selector\(i + 1)_arity\(arity)")
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: paramName,
                    fqName: functionFQName + [paramInternalName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(funcSymbol, for: paramSymbol)
                paramSymbols.append(paramSymbol)
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: paramTypes,
                    returnType: comparatorType,
                    isSuspend: false,
                    valueParameterSymbols: paramSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: arity),
                    valueParameterIsVararg: Array(repeating: false, count: arity),
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

    private func registerNullsComparators(
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

        for (name, extLink) in [
            ("nullsFirst", "kk_comparator_nulls_first"),
            ("nullsLast", "kk_comparator_nulls_last"),
        ] {
            let memberName = interner.intern(name)
            let memberFQName = comparatorFQName + [memberName]
            if let existing = symbols.lookup(fqName: memberFQName) {
                symbols.setExternalLinkName(extLink, for: existing)
                continue
            }

            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(comparatorSymbol, for: memberSymbol)
            symbols.setExternalLinkName(extLink, for: memberSymbol)
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

    /// Register compareValues and compareValuesBy top-level functions (STDLIB-xxx).
    ///
    /// - `compareValues(a: T?, b: T?): Int` → `kk_compareValues`
    /// - `compareValuesBy(a: T, b: T, selector: (T) -> Comparable<*>?): Int` → `kk_compareValuesBy1`
    /// - `compareValuesBy(a: T, b: T, vararg selectors: (T) -> Comparable<*>?): Int` → `kk_compareValuesBy`
    private func registerCompareValuesAndCompareValuesBy(
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
        let nullableTParamType = types.makeNullable(tParamType)

        // compareValues(a: T?, b: T?): Int
        do {
            let functionName = interner.intern("compareValues")
            let functionFQName = comparisonsPkg + [functionName]
            let extLink = "kk_compareValues"

            if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes.count == 2 && sig.returnType == types.intType
            }) {
                if let existing = symbols.lookupAll(fqName: functionFQName).first {
                    symbols.setExternalLinkName(extLink, for: existing)
                }
            } else {
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

                let aName = interner.intern("a")
                let bName = interner.intern("b")
                let aSymbol = symbols.define(
                    kind: .valueParameter,
                    name: aName,
                    fqName: functionFQName + [aName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let bSymbol = symbols.define(
                    kind: .valueParameter,
                    name: bName,
                    fqName: functionFQName + [bName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(funcSymbol, for: aSymbol)
                symbols.setParentSymbol(funcSymbol, for: bSymbol)

                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [nullableTParamType, nullableTParamType],
                        returnType: types.intType,
                        isSuspend: false,
                        valueParameterSymbols: [aSymbol, bSymbol],
                        valueParameterHasDefaultValues: [false, false],
                        valueParameterIsVararg: [false, false],
                        typeParameterSymbols: [tParamSymbol],
                        typeParameterUpperBoundsList: [[]]
                    ),
                    for: funcSymbol
                )
            }
        }

        // compareValuesBy(a: T, b: T, selector: (T) -> Comparable<*>?): Int
        do {
            let functionName = interner.intern("compareValuesBy")
            let functionFQName = comparisonsPkg + [functionName]
            let extLink = "kk_compareValuesBy1"

            let selectorType = types.make(.functionType(FunctionType(
                params: [tParamType],
                returnType: types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))

            let paramTypes = [tParamType, tParamType, selectorType]

            if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == paramTypes && sig.returnType == types.intType
            }) {
                if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                    guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                    return sig.parameterTypes == paramTypes && sig.returnType == types.intType
                }) {
                    symbols.setExternalLinkName(extLink, for: existing)
                }
            } else {
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

                let aName = interner.intern("a")
                let bName = interner.intern("b")
                let selectorParamName = interner.intern("selector")
                // Use qualified fqName to avoid collision with vararg overload
                let aInternalName = interner.intern("a_compareValuesBy1")
                let bInternalName = interner.intern("b_compareValuesBy1")
                let selectorInternalName = interner.intern("selector_compareValuesBy1")
                let aSymbol = symbols.define(
                    kind: .valueParameter,
                    name: aName,
                    fqName: functionFQName + [aInternalName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let bSymbol = symbols.define(
                    kind: .valueParameter,
                    name: bName,
                    fqName: functionFQName + [bInternalName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let selectorSymbol = symbols.define(
                    kind: .valueParameter,
                    name: selectorParamName,
                    fqName: functionFQName + [selectorInternalName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(funcSymbol, for: aSymbol)
                symbols.setParentSymbol(funcSymbol, for: bSymbol)
                symbols.setParentSymbol(funcSymbol, for: selectorSymbol)

                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: paramTypes,
                        returnType: types.intType,
                        isSuspend: false,
                        valueParameterSymbols: [aSymbol, bSymbol, selectorSymbol],
                        valueParameterHasDefaultValues: [false, false, false],
                        valueParameterIsVararg: [false, false, false],
                        typeParameterSymbols: [tParamSymbol],
                        typeParameterUpperBoundsList: [[]]
                    ),
                    for: funcSymbol
                )
            }
        }

        // compareValuesBy(a: T, b: T, selector1, selector2): Int (2-selector variant)
        do {
            let functionName = interner.intern("compareValuesBy")
            let functionFQName = comparisonsPkg + [functionName]
            let extLink = "kk_compareValuesBy"

            let selectorType = types.make(.functionType(FunctionType(
                params: [tParamType],
                returnType: types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))

            for arity in 2...3 {
                let selectorParams = Array(repeating: selectorType, count: arity)
                let paramTypes = [tParamType, tParamType] + selectorParams
                let extLinkArity = arity == 2 ? "kk_compareValuesBy" : "kk_compareValuesBy3"

                if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
                    guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                    return sig.parameterTypes == paramTypes && sig.returnType == types.intType
                }) {
                    if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                        guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                        return sig.parameterTypes == paramTypes && sig.returnType == types.intType
                    }) {
                        symbols.setExternalLinkName(extLinkArity, for: existing)
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
                symbols.setExternalLinkName(extLinkArity, for: funcSymbol)

                let aName = interner.intern("a")
                let bName = interner.intern("b")
                let aInternalName = interner.intern("a_compareValuesBy_arity\(arity)")
                let bInternalName = interner.intern("b_compareValuesBy_arity\(arity)")
                let aSymbol = symbols.define(
                    kind: .valueParameter,
                    name: aName,
                    fqName: functionFQName + [aInternalName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let bSymbol = symbols.define(
                    kind: .valueParameter,
                    name: bName,
                    fqName: functionFQName + [bInternalName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(funcSymbol, for: aSymbol)
                symbols.setParentSymbol(funcSymbol, for: bSymbol)

                var paramSymbols: [SymbolID] = [aSymbol, bSymbol]
                for i in 0..<arity {
                    let paramName = interner.intern("selector\(i + 1)")
                    let paramInternalName = interner.intern("selector\(i + 1)_compareValuesBy_arity\(arity)")
                    let paramSymbol = symbols.define(
                        kind: .valueParameter,
                        name: paramName,
                        fqName: functionFQName + [paramInternalName],
                        declSite: nil,
                        visibility: .private,
                        flags: [.synthetic]
                    )
                    symbols.setParentSymbol(funcSymbol, for: paramSymbol)
                    paramSymbols.append(paramSymbol)
                }

                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: paramTypes,
                        returnType: types.intType,
                        isSuspend: false,
                        valueParameterSymbols: paramSymbols,
                        valueParameterHasDefaultValues: Array(repeating: false, count: 2 + arity),
                        valueParameterIsVararg: Array(repeating: false, count: 2 + arity),
                        typeParameterSymbols: [tParamSymbol],
                        typeParameterUpperBoundsList: [[]]
                    ),
                    for: funcSymbol
                )
            }
        }
    }
}
