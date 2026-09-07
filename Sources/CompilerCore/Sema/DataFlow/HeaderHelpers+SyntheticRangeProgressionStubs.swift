
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
        _ = syntheticNominalType(
            named: "Random",
            in: [kotlinName, interner.intern("random")],
            symbols: symbols,
            types: types,
            interner: interner
        )
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
        let openEndRangeSymbol = registerSyntheticOpenEndRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticRangeInterfaceStubs(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticRangeUntilFunction(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Byte/Short until produce Int ranges; mixed Int/Long calls widen to Long.
        registerSyntheticRangeUntilStub(
            ownerSymbol: rangesPackageSymbol,
            receiverType: types.intType,
            parameterType: types.intType,
            returnType: types.intType,
            externalLinkName: "__kk_op_rangeUntil",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRangeUntilStub(
            ownerSymbol: rangesPackageSymbol,
            receiverType: types.intType,
            parameterType: types.longType,
            returnType: types.longType,
            externalLinkName: "__kk_op_rangeUntil",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRangeUntilStub(
            ownerSymbol: rangesPackageSymbol,
            receiverType: types.longType,
            parameterType: types.intType,
            returnType: types.longType,
            externalLinkName: "__kk_op_rangeUntil",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRangeUntilStub(
            ownerSymbol: rangesPackageSymbol,
            receiverType: types.longType,
            parameterType: types.longType,
            returnType: types.longType,
            externalLinkName: "__kk_op_rangeUntil",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRangeUntilStub(
            ownerSymbol: rangesPackageSymbol,
            receiverType: types.byteType,
            parameterType: types.byteType,
            returnType: types.intType,
            externalLinkName: "__kk_op_rangeUntil",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRangeUntilStub(
            ownerSymbol: rangesPackageSymbol,
            receiverType: types.shortType,
            parameterType: types.shortType,
            returnType: types.intType,
            externalLinkName: "__kk_op_rangeUntil",
            symbols: symbols,
            interner: interner
        )

        // Complete the signed until overload matrix: Byte/Short/Int/Long with
        // any combination; the result is Long when either side is Long, Int
        // otherwise. The Int/Int, Int/Long, Long/Int, Long/Long, Byte/Byte,
        // and Short/Short cases are already registered above to keep symbol
        // ordering stable for existing golden outputs.
        let signedRangeUntilTypes: [TypeID] = [
            types.byteType,
            types.shortType,
            types.intType,
            types.longType,
        ]
        for receiverType in signedRangeUntilTypes {
            for parameterType in signedRangeUntilTypes {
                let alreadyRegistered: Bool
                if receiverType == types.intType {
                    alreadyRegistered = parameterType == types.intType || parameterType == types.longType
                } else if receiverType == types.longType {
                    alreadyRegistered = parameterType == types.intType || parameterType == types.longType
                } else if receiverType == types.byteType {
                    alreadyRegistered = parameterType == types.byteType
                } else if receiverType == types.shortType {
                    alreadyRegistered = parameterType == types.shortType
                } else {
                    alreadyRegistered = false
                }
                guard !alreadyRegistered else { continue }

                let returnType: TypeID = (receiverType == types.longType || parameterType == types.longType)
                    ? types.longType
                    : types.intType
                registerSyntheticRangeUntilStub(
                    ownerSymbol: rangesPackageSymbol,
                    receiverType: receiverType,
                    parameterType: parameterType,
                    returnType: returnType,
                    externalLinkName: "__kk_op_rangeUntil",
                    symbols: symbols,
                    interner: interner
                )
            }
        }

        registerSyntheticProgressionStub(
            named: "IntProgression",
            elementType: types.intType,
            stepType: types.intType,
            externalLinkName: "__kk_int_progression_fromClosedRange",
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
            externalLinkName: "__kk_long_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticProgressionStub(
            named: "CharProgression",
            elementType: types.charType,
            stepType: types.intType,
            externalLinkName: "__kk_char_progression_fromClosedRange",
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
            externalLinkName: "__kk_uint_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticUIntRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticProgressionStub(
            named: "ULongProgression",
            elementType: types.ulongType,
            stepType: types.intType,
            externalLinkName: "__kk_ulong_progression_fromClosedRange",
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticULongRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticIntRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticLongRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticCharRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticClosedRangeStub(
            rangesPackageSymbol: rangesPackageSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    /// KSP-652: the `OpenEndRange<T>` declaration is source-backed by
    /// `Stdlib/kotlin/ranges/Ranges.kt`, which reuses this shell on bundle load (the
    /// `.synthetic` flag is cleared then). The shell has to stay because `rangeUntil` and the
    /// concrete range conformances are registered before bundled headers are collected and need
    /// the symbol to already exist; its members stay compiler-side residuals for the same
    /// reason as the `ClosedRange` ones. See `HeaderHelpers+SyntheticRangeInterfaceStubs.swift`.
    private func registerSyntheticOpenEndRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let className = interner.intern("OpenEndRange")
        let classFQName = rangesFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            let created = symbols.define(
                kind: .interface,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rangesPackageSymbol, for: created)
            classSymbol = created
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = classFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            let created = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(classSymbol, for: created)
            typeParamSymbol = created
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let openEndRangeType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)

        registerProgressionProperty(
            named: "start",
            ownerSymbol: classSymbol,
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerProgressionProperty(
            named: "endExclusive",
            ownerSymbol: classSymbol,
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "contains",
            ownerSymbol: classSymbol,
            receiverType: openEndRangeType,
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction],
            classTypeParameterCount: 1,
            // KSP-1288 adds source-backed cross-type overloads with the same
            // arity. Keep this generic interface residual alongside them.
            allowBundledSourceOverlap: true,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "isEmpty",
            ownerSymbol: classSymbol,
            receiverType: openEndRangeType,
            parameterTypes: [],
            returnType: types.booleanType,
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        return classSymbol
    }

    private func registerSyntheticRangeUntilFunction(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        openEndRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("rangeUntil")
        let functionFQName = rangesFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
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
        let comparableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Comparable"),
        ]
        guard let comparableSymbol = symbols.lookup(fqName: comparableFQName) else {
            return
        }
        let comparableType = types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(typeParamType)],
            nullability: .nonNull
        )))
        let openEndRangeType = types.make(.classType(ClassType(
            classSymbol: openEndRangeSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == typeParamType
                && signature.parameterTypes == [typeParamType]
                && signature.returnType == openEndRangeType
        }) {
            return
        }

        let parameterName = interner.intern("that")
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: functionFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(rangesPackageSymbol, for: functionSymbol)
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
        symbols.setExternalLinkName("__kk_op_rangeUntil", for: functionSymbol)
        symbols.setTypeParameterUpperBounds([comparableType], for: typeParamSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: typeParamType,
                parameterTypes: [typeParamType],
                returnType: openEndRangeType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[comparableType]]
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticRangeUntilStub(
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameterType: TypeID,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }

        let functionName = interner.intern("until")
        let functionFQName = ownerInfo.fqName + [functionName]

        // KSP-456: bundled Kotlin sources provide class-returning `until` extensions.
        // Skip the synthetic primitive-return stub for any receiver type already
        // covered by bundled source.
        guard let types = BundledSyntheticStubRegistration.types else {
            return
        }
        let bundledIndex = BundledSyntheticStubRegistration.bundledIndex
        if let owner = BundledDeclarationIndex.receiverOwnerFQName(
            for: receiverType,
            symbols: symbols,
            types: types,
            interner: interner
        ), shouldSkipSyntheticStub(
            bundledIndex: bundledIndex,
            ownerFQName: owner,
            name: functionName,
            arity: 1
        ) {
            return
        }

        let parameterName = interner.intern("to")
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: functionFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [parameterType],
                returnType: returnType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: functionSymbol
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
                flags: name == "ULongProgression" ? [.synthetic, .openType] : [.synthetic]
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
        registerIterableSupertype(
            classSymbol: classSymbol,
            elementType: elementType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionName = interner.intern("fromClosedRange")
        let functionFQName = companionInfo.fqName + [functionName]
        let bundledIndex = BundledSyntheticStubRegistration.bundledIndex
        let fromClosedRangeExists = bundledIndex.contains(
            ownerFQName: companionInfo.fqName,
            name: functionName,
            arity: 3
        ) || symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == companionType
                && signature.parameterTypes == [elementType, elementType, stepType]
        })

        if !fromClosedRangeExists {
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
        }

        let listType = syntheticListType(elementType: elementType, symbols: symbols, types: types, interner: interner)
        let firstLastRuntime: (String, String)
        switch name {
        case "UIntProgression":
            firstLastRuntime = ("kk_uint_range_first", "kk_uint_range_last")
        case "ULongProgression":
            firstLastRuntime = ("kk_ulong_range_first", "kk_ulong_range_last")
        case "LongProgression":
            firstLastRuntime = ("__kk_range_first", "__kk_range_last")
        default:
            firstLastRuntime = ("__kk_range_first", "__kk_range_last")
        }
        let stepRuntime: String
        switch name {
        case "UIntProgression": stepRuntime = "kk_uint_range_step"
        case "ULongProgression": stepRuntime = "kk_ulong_range_step"
        case "LongProgression": stepRuntime = "kk_long_range_step"
        default: stepRuntime = "kk_range_step"
        }
        let isEmptyRuntime: String
        switch name {
        case "UIntProgression": isEmptyRuntime = "kk_uint_range_isEmpty"
        case "ULongProgression": isEmptyRuntime = "kk_ulong_range_isEmpty"
        default: isEmptyRuntime = "__kk_range_isEmpty"
        }
        let reversedRuntime: String
        let toListRuntime: String
        switch name {
        case "UIntProgression":
            reversedRuntime = "kk_uint_range_reversed"
            toListRuntime = "kk_uint_range_toList"
        case "ULongProgression":
            reversedRuntime = "kk_ulong_range_reversed"
            toListRuntime = "kk_ulong_range_toList"
        case "LongProgression":
            reversedRuntime = "__kk_range_reversed"
            toListRuntime = "kk_long_range_toList"
        case "CharProgression":
            reversedRuntime = "__kk_range_reversed"
            toListRuntime = "kk_char_range_toList"
        default:
            reversedRuntime = "__kk_range_reversed"
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
            externalLinkName: name == "ULongProgression" ? "__kk_ulong_step" : (name == "UIntProgression" ? "__kk_uint_step" : (name == "CharProgression" ? "__kk_char_range_step" : "__kk_op_step")),
            symbols: symbols,
            interner: interner
        )
    }

    func registerProgressionProperty(
        named name: String,
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        externalLinkName: String? = nil,
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
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        }
    }

    func registerProgressionMethod(
        named name: String,
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        externalLinkName: String? = nil,
        flags: SymbolFlags = [.synthetic],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        allowBundledSourceOverlap: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        let ownerName = interner.resolve(ownerInfo.name)
        let isUnsignedProgressionOwner = ownerName == "UIntRange"
            || ownerName == "UIntProgression"
            || ownerName == "ULongRange"
            || ownerName == "ULongProgression"
        let shouldDeferToBundledToList = functionName == interner.intern("toList")
            && !isUnsignedProgressionOwner
        let bundledSkipReceiverType: TypeID? = shouldDeferToBundledToList ? receiverType : nil
        if !allowBundledSourceOverlap,
           let types = BundledSyntheticStubRegistration.types,
           BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: ownerInfo.fqName,
               // Most progression helpers are class members; their receiver is the dispatch self type,
               // not an extension receiver that should be skipped before bundled declarations load.
               // Signed and Char `toList` helpers are supplied by bundled stdlib, so defer them to the
               // bundled-index guard. Unsigned progressions still need their synthetic fallback.
               receiverType: bundledSkipReceiverType,
               name: functionName,
               arity: parameterTypes.count,
               symbols: symbols,
               types: types,
               interner: interner
           )
        {
            return
        }
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.typeParameterSymbols == typeParameterSymbols
                && signature.classTypeParameterCount == classTypeParameterCount
        }) {
            return
        }

        let parameterSymbols = parameterTypes.indices.map { index in
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
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
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

    private func registerSyntheticClosedRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("ClosedRange")
        let classFQName = rangesFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            let created = symbols.define(
                kind: .interface,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rangesPackageSymbol, for: created)
            classSymbol = created
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = classFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let rangeType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        registerProgressionProperty(
            named: "start",
            ownerSymbol: classSymbol,
            propertyType: typeParamType,
            externalLinkName: "__kk_range_first",
            symbols: symbols,
            interner: interner
        )
        registerProgressionProperty(
            named: "endInclusive",
            ownerSymbol: classSymbol,
            propertyType: typeParamType,
            externalLinkName: "__kk_range_last",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "contains",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            externalLinkName: "kk_op_contains",
            flags: [.synthetic, .operatorFunction],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "isEmpty",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: types.booleanType,
            externalLinkName: "__kk_range_isEmpty",
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerClosedRangeImplementation(
            named: "IntRange",
            elementType: types.intType,
            closedRangeSymbol: classSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerClosedRangeImplementation(
            named: "LongRange",
            elementType: types.longType,
            closedRangeSymbol: classSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerClosedRangeImplementation(
            named: "UIntRange",
            elementType: types.uintType,
            closedRangeSymbol: classSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerClosedRangeImplementation(
            named: "ULongRange",
            elementType: types.ulongType,
            closedRangeSymbol: classSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerClosedRangeImplementation(
            named: "CharRange",
            elementType: types.charType,
            closedRangeSymbol: classSymbol,
            rangesFQName: rangesFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerIterableSupertype(
        classSymbol: SymbolID,
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableInterfaceSymbol = symbols.lookup(fqName: iterableFQName) else {
            return
        }
        appendNominalSupertype(
            classSymbol: classSymbol,
            supertype: iterableInterfaceSymbol,
            typeArgs: [.out(elementType)],
            symbols: symbols,
            types: types
        )
    }

    func registerOpenEndRangeConformance(
        classSymbol: SymbolID,
        elementType: TypeID,
        openEndRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem
    ) {
        appendNominalSupertype(
            classSymbol: classSymbol,
            supertype: openEndRangeSymbol,
            typeArgs: [.invariant(elementType)],
            symbols: symbols,
            types: types
        )
    }

    private func appendNominalSupertype(
        classSymbol: SymbolID,
        supertype: SymbolID,
        typeArgs: [TypeArg],
        symbols: SymbolTable,
        types: TypeSystem
    ) {
        var directSupertypes = symbols.directSupertypes(for: classSymbol)
        if !directSupertypes.contains(supertype) {
            directSupertypes.append(supertype)
            symbols.setDirectSupertypes(directSupertypes, for: classSymbol)
        }
        var nominalSupertypes = types.directNominalSupertypes(for: classSymbol)
        if !nominalSupertypes.contains(supertype) {
            nominalSupertypes.append(supertype)
            types.setNominalDirectSupertypes(nominalSupertypes, for: classSymbol)
        }
        symbols.setSupertypeTypeArgs(typeArgs, for: classSymbol, supertype: supertype)
        types.setNominalSupertypeTypeArgs(typeArgs, for: classSymbol, supertype: supertype)
    }

    func registerOpenEndRangeComparableUpperBound(
        comparableSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let openEndRangeFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern("OpenEndRange"),
        ]
        guard let openEndRangeSymbol = symbols.lookup(fqName: openEndRangeFQName) else {
            return
        }
        let typeParamFQName = openEndRangeFQName + [interner.intern("T")]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else {
            return
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let comparableUpperBound = types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setTypeParameterUpperBounds([comparableUpperBound], for: typeParamSymbol)
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: openEndRangeSymbol)
    }

    private func registerClosedRangeImplementation(
        named name: String,
        elementType: TypeID,
        closedRangeSymbol: SymbolID,
        rangesFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = rangesFQName + [className]
        guard let classSymbol = symbols.lookup(fqName: classFQName) else {
            return
        }
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableInterfaceSymbol = symbols.lookup(fqName: iterableFQName) else {
            return
        }
        symbols.setDirectSupertypes([iterableInterfaceSymbol, closedRangeSymbol], for: classSymbol)
        types.setNominalDirectSupertypes([iterableInterfaceSymbol, closedRangeSymbol], for: classSymbol)
        symbols.setSupertypeTypeArgs([.out(elementType)], for: classSymbol, supertype: iterableInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(elementType)], for: classSymbol, supertype: iterableInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.invariant(elementType)], for: classSymbol, supertype: closedRangeSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(elementType)], for: classSymbol, supertype: closedRangeSymbol)
    }

    func patchSyntheticClosedRangeTypeParameterUpperBound(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let comparableSymbol = types.comparableInterfaceSymbol else {
            return
        }
        let closedRangeFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern("ClosedRange"),
        ]
        guard symbols.lookup(fqName: closedRangeFQName) != nil else {
            return
        }
        let typeParamFQName = closedRangeFQName + [interner.intern("T")]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else {
            return
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let comparableType = types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setTypeParameterUpperBounds([comparableType], for: typeParamSymbol)
    }
}
