import Foundation

/// Synthetic stubs for Comparator, compareBy, compareByDescending (STDLIB-175),
/// thenBy, thenByDescending, thenDescending, thenComparator, reversed (STDLIB-176),
/// naturalOrder, reverseOrder (STDLIB-177), Array.binarySearch (STDLIB-COL-BSEARCH-004).
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

        registerArrayBinarySearchComparator(
            symbols: symbols,
            types: types,
            interner: interner,
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

        for (name, extLink) in [
            ("compareByPrimitive", "kk_comparator_from_selector_primitive"),
            ("compareByDescendingPrimitive", "kk_comparator_from_selector_primitive_descending"),
        ] {
            let functionName = interner.intern(name)
            let functionFQName = comparisonsPkg + [functionName]
            let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == [selectorType] && sig.returnType == comparatorType
            })
            if let existing {
                symbols.setExternalLinkName(extLink, for: existing)
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

        for (name, extLink) in [
            ("compareBy", "kk_comparator_from_comparator_selector"),
            ("compareByDescending", "kk_comparator_from_comparator_selector_descending"),
        ] {
            let functionName = interner.intern(name)
            let functionFQName = comparisonsPkg + [functionName]
            let kParamName = interner.intern("K")
            let kParamFQName = functionFQName + [kParamName]
            let kParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: kParamFQName) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: kParamName,
                    fqName: kParamFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            let kParamType = types.make(.typeParam(TypeParamType(
                symbol: kParamSymbol,
                nullability: .nonNull
            )))
            let keyComparatorType = types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(kParamType)],
                nullability: .nonNull
            )))
            let keySelectorType = types.make(.functionType(FunctionType(
                params: [tParamType],
                returnType: kParamType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == [keyComparatorType, keySelectorType] &&
                    sig.returnType == comparatorType
            }) {
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

            let comparatorParamName = interner.intern("comparator")
            let comparatorParamSymbol = symbols.define(
                kind: .valueParameter,
                name: comparatorParamName,
                fqName: functionFQName + [comparatorParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let selectorParamName = interner.intern("selector")
            let selectorParamSymbol = symbols.define(
                kind: .valueParameter,
                name: selectorParamName,
                fqName: functionFQName + [selectorParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(funcSymbol, for: comparatorParamSymbol)
            symbols.setParentSymbol(funcSymbol, for: selectorParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [keyComparatorType, keySelectorType],
                    returnType: comparatorType,
                    isSuspend: false,
                    valueParameterSymbols: [comparatorParamSymbol, selectorParamSymbol],
                    valueParameterHasDefaultValues: [false, false],
                    valueParameterIsVararg: [false, false],
                    typeParameterSymbols: [tParamSymbol, kParamSymbol],
                    typeParameterUpperBoundsList: [[], []]
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

        let varargExtLink = "kk_comparator_from_multi_selectors_vararg"
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [selectorType] &&
                sig.returnType == comparatorType &&
                sig.valueParameterIsVararg == [true]
        }) {
            if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == [selectorType] &&
                    sig.returnType == comparatorType &&
                    sig.valueParameterIsVararg == [true]
            }) {
                symbols.setExternalLinkName(varargExtLink, for: existing)
            }
            return
        }

        let varargFuncSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: varargFuncSymbol)
        symbols.setExternalLinkName(varargExtLink, for: varargFuncSymbol)

        let selectorsParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("selectors"),
            fqName: functionFQName + [interner.intern("selectors_vararg")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(varargFuncSymbol, for: selectorsParamSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [selectorType],
                returnType: comparatorType,
                isSuspend: false,
                valueParameterSymbols: [selectorsParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]]
            ),
            for: varargFuncSymbol
        )
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
        let comparisonType = types.make(.functionType(FunctionType(
            params: [tParamType, tParamType],
            returnType: types.intType,
            isSuspend: false,
            nullability: .nonNull
        )))

        for (name, extLink, parameterType, parameterName) in [
            ("thenBy", "kk_comparator_then_by", selectorType, "selector"),
            ("thenByDescending", "kk_comparator_then_by_descending", selectorType, "selector"),
            ("thenDescending", "kk_comparator_then_descending", comparisonType, "comparator"),
        ] {
            let memberName = interner.intern(name)
            let memberFQName = comparatorFQName + [memberName]
            if symbols.lookup(fqName: memberFQName) != nil { continue }

            let parameterName = interner.intern(parameterName)
            let selectorParamSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
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
                    parameterTypes: [parameterType],
                    returnType: receiverType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        let comparisonName = interner.intern("thenComparator")
        let comparisonFQName = comparatorFQName + [comparisonName]
        if symbols.lookup(fqName: comparisonFQName) == nil {
            let comparisonParamName = interner.intern("comparison")
            let comparisonParamSymbol = symbols.define(
                kind: .valueParameter,
                name: comparisonParamName,
                fqName: comparisonFQName + [comparisonParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let comparisonSymbol = symbols.define(
                kind: .function,
                name: comparisonName,
                fqName: comparisonFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(comparatorSymbol, for: comparisonSymbol)
            symbols.setParentSymbol(comparisonSymbol, for: comparisonParamSymbol)
            symbols.setExternalLinkName("kk_comparator_then_comparator", for: comparisonSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [comparisonType],
                    returnType: receiverType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: comparisonSymbol
            )
        }

        let kParamName = interner.intern("K")
        do {
            let thenByFQName = comparatorFQName + [interner.intern("thenBy")]
            let thenByKParamFQName = thenByFQName + [kParamName]
            let thenByKParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: thenByKParamFQName) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: kParamName,
                    fqName: thenByKParamFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            let thenByKParamType = types.make(.typeParam(TypeParamType(
                symbol: thenByKParamSymbol,
                nullability: .nonNull
            )))
            let keyComparatorType = types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(thenByKParamType)],
                nullability: .nonNull
            )))
            let keySelectorType = types.make(.functionType(FunctionType(
                params: [tParamType],
                returnType: thenByKParamType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if !symbols.lookupAll(fqName: thenByFQName).contains(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == [keyComparatorType, keySelectorType] &&
                    sig.returnType == receiverType
            }) {
                let comparatorParamName = interner.intern("comparator")
                let comparatorParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: comparatorParamName,
                    fqName: thenByFQName + [interner.intern("comparator_with_selector")],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let selectorParamName = interner.intern("selector")
                let selectorParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: selectorParamName,
                    fqName: thenByFQName + [interner.intern("selector_with_comparator")],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: interner.intern("thenBy"),
                    fqName: thenByFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(comparatorSymbol, for: memberSymbol)
                symbols.setParentSymbol(memberSymbol, for: comparatorParamSymbol)
                symbols.setParentSymbol(memberSymbol, for: selectorParamSymbol)
                symbols.setExternalLinkName("kk_comparator_then_by_comparator_selector", for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [keyComparatorType, keySelectorType],
                        returnType: receiverType,
                        isSuspend: false,
                        valueParameterSymbols: [comparatorParamSymbol, selectorParamSymbol],
                        valueParameterHasDefaultValues: [false, false],
                        valueParameterIsVararg: [false, false],
                        typeParameterSymbols: [tParamSymbol, thenByKParamSymbol],
                        typeParameterUpperBoundsList: [[], []],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }
        }

        do {
            let thenByDescendingFQName = comparatorFQName + [interner.intern("thenByDescending")]
            let thenByDescendingKParamFQName = thenByDescendingFQName + [kParamName]
            let thenByDescendingKParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: thenByDescendingKParamFQName) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: kParamName,
                    fqName: thenByDescendingKParamFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            let thenByDescendingKParamType = types.make(.typeParam(TypeParamType(
                symbol: thenByDescendingKParamSymbol,
                nullability: .nonNull
            )))
            let keyComparatorType = types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(thenByDescendingKParamType)],
                nullability: .nonNull
            )))
            let keySelectorType = types.make(.functionType(FunctionType(
                params: [tParamType],
                returnType: thenByDescendingKParamType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if !symbols.lookupAll(fqName: thenByDescendingFQName).contains(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == [keyComparatorType, keySelectorType] &&
                    sig.returnType == receiverType
            }) {
                let comparatorParamName = interner.intern("comparator")
                let comparatorParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: comparatorParamName,
                    fqName: thenByDescendingFQName + [interner.intern("comparator_with_selector")],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let selectorParamName = interner.intern("selector")
                let selectorParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: selectorParamName,
                    fqName: thenByDescendingFQName + [interner.intern("selector_with_comparator")],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: interner.intern("thenByDescending"),
                    fqName: thenByDescendingFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(comparatorSymbol, for: memberSymbol)
                symbols.setParentSymbol(memberSymbol, for: comparatorParamSymbol)
                symbols.setParentSymbol(memberSymbol, for: selectorParamSymbol)
                symbols.setExternalLinkName(
                    "kk_comparator_then_by_descending_comparator_selector",
                    for: memberSymbol
                )
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [keyComparatorType, keySelectorType],
                        returnType: receiverType,
                        isSuspend: false,
                        valueParameterSymbols: [comparatorParamSymbol, selectorParamSymbol],
                        valueParameterHasDefaultValues: [false, false],
                        valueParameterIsVararg: [false, false],
                        typeParameterSymbols: [tParamSymbol, thenByDescendingKParamSymbol],
                        typeParameterUpperBoundsList: [[], []],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }
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

    private func registerArrayBinarySearchComparator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparatorSymbol: SymbolID
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let arrayName = interner.intern("Array")
        let arrayFQName = kotlinPkg + [arrayName]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return
        }
        let tParamName = interner.intern("T")
        let tParamFQName = arrayFQName + [tParamName]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else {
            return
        }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))
        let comparatorType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))

        let memberName = interner.intern("binarySearch")
        let memberFQName = arrayFQName + [memberName]
        let expectedParameterTypes: [TypeID] = [
            tParamType,
            comparatorType,
            types.intType,
            types.intType,
        ]
        if symbols.lookupAll(fqName: memberFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.parameterTypes == expectedParameterTypes
                && signature.returnType == types.intType
        }) {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(arraySymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_array_binarySearch_compare", for: memberSymbol)

        let elementParamName = interner.intern("element")
        let comparatorParamName = interner.intern("comparator")
        let fromIndexParamName = interner.intern("fromIndex")
        let toIndexParamName = interner.intern("toIndex")
        let valueParameters: [SymbolID] = [
            symbols.define(
                kind: .valueParameter,
                name: elementParamName,
                fqName: memberFQName + [elementParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            ),
            symbols.define(
                kind: .valueParameter,
                name: comparatorParamName,
                fqName: memberFQName + [comparatorParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            ),
            symbols.define(
                kind: .valueParameter,
                name: fromIndexParamName,
                fqName: memberFQName + [fromIndexParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            ),
            symbols.define(
                kind: .valueParameter,
                name: toIndexParamName,
                fqName: memberFQName + [toIndexParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            ),
        ]

        for parameterSymbol in valueParameters {
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [.invariant(tParamType)],
                    nullability: .nonNull
                ))),
                parameterTypes: expectedParameterTypes,
                returnType: types.intType,
                valueParameterSymbols: valueParameters,
                valueParameterHasDefaultValues: [false, false, false, false],
                valueParameterIsVararg: [false, false, false, false],
                typeParameterSymbols: [tParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

}
