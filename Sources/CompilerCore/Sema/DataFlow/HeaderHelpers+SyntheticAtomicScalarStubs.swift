
/// Scalar atomic value boxes (`AtomicInt`/`AtomicLong`/`AtomicBoolean`,
/// `java.util.concurrent.atomic.AtomicInteger`, and `AtomicReference<T>`),
/// extracted from the Atomic residual registration surface. `AtomicInteger`
/// shares the `__kk_atomic_int_*` bridge prefix with `AtomicInt` (see
/// `Stdlib/kotlin/concurrent/AtomicMigration.kt`) and is a live, tested
/// direct-construction surface — not a target-out cleanup pocket.
extension DataFlowSemaPhase {
    func registerAtomicScalarFamily(
        packageFQName: [InternedString],
        className: String,
        constructorLinkName: String,
        valueType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        includeArithmetic: Bool,
        includeIncrementAndGetAlias: Bool = false,
        includeGetAndIncrementAlias: Bool = false,
        includeGetAndDecrementAlias: Bool = false,
        includeGetAndSetAlias: Bool = false,
        includeGetAndAddAlias: Bool = false,
        includeDecrementAndGetAlias: Bool = false,
        includeAddAndGetAlias: Bool = false,
        includeCompareAndSet: Bool = true,
        compareAndSetLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let symbol = ensureClassSymbol(
            named: className,
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        let ownerType = types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: symbol)

        registerAtomicConstructor(
            ownerSymbol: symbol,
            ownerType: ownerType,
            externalLinkName: constructorLinkName,
            paramType: valueType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: symbol,
            valueType: valueType,
            getterLinkName: "\(prefix)_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: symbol,
            ownerType: ownerType,
            valueType: valueType,
            boolType: boolType,
            unitType: unitType,
            prefix: prefix,
            includeGetAndSetAlias: includeGetAndSetAlias,
            includeCompareAndSet: includeCompareAndSet,
            compareAndSetLinkName: compareAndSetLinkName,
            symbols: symbols,
            interner: interner
        )

        if includeArithmetic {
            registerAtomicArithmeticMethods(
                ownerSymbol: symbol,
                ownerType: ownerType,
                valueType: valueType,
                prefix: prefix,
                includeIncrementAndGetAlias: includeIncrementAndGetAlias,
                includeGetAndIncrementAlias: includeGetAndIncrementAlias,
                includeGetAndDecrementAlias: includeGetAndDecrementAlias,
                includeGetAndAddAlias: includeGetAndAddAlias,
                includeDecrementAndGetAlias: includeDecrementAndGetAlias,
                includeAddAndGetAlias: includeAddAndGetAlias,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerAtomicArithmeticMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        includeIncrementAndGetAlias: Bool = false,
        includeGetAndIncrementAlias: Bool = false,
        includeGetAndDecrementAlias: Bool = false,
        includeGetAndAddAlias: Bool = false,
        includeDecrementAndGetAlias: Bool = false,
        includeAddAndGetAlias: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // fetchAndAdd(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndAdd", externalLinkName: "\(prefix)_fetchAndAdd",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeGetAndAddAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "getAndAdd", externalLinkName: "\(prefix)_fetchAndAdd",
                returnType: valueType, parameters: [(name: "delta", type: valueType)],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // addAndFetch(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "addAndFetch", externalLinkName: "\(prefix)_addAndFetch",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeAddAndGetAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "addAndGet", externalLinkName: "\(prefix)_addAndFetch",
                returnType: valueType, parameters: [(name: "delta", type: valueType)],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // fetchAndIncrement() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndIncrement", externalLinkName: "\(prefix)_fetchAndIncrement",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeGetAndIncrementAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "getAndIncrement", externalLinkName: "\(prefix)_fetchAndIncrement",
                returnType: valueType, parameters: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // fetchAndDecrement() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndDecrement", externalLinkName: "\(prefix)_fetchAndDecrement",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeGetAndDecrementAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "getAndDecrement", externalLinkName: "\(prefix)_fetchAndDecrement",
                returnType: valueType, parameters: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // incrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "incrementAndFetch", externalLinkName: "\(prefix)_incrementAndFetch",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeIncrementAndGetAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "incrementAndGet", externalLinkName: "\(prefix)_incrementAndFetch",
                returnType: valueType, parameters: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // decrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "decrementAndFetch", externalLinkName: "\(prefix)_decrementAndFetch",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeDecrementAndGetAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "decrementAndGet", externalLinkName: "\(prefix)_decrementAndFetch",
                returnType: valueType, parameters: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
    }

    /// Registers `kotlin.concurrent.AtomicReference<T>` (and the shared
    /// `kotlin.concurrent.atomics.AtomicReference<T>` surface via its caller),
    /// backed by `kk_atomic_ref_*` ABI functions. CAS uses identity semantics.
    func registerAtomicReferenceStubs(
        ownerPackage: [InternedString],
        ownerPackageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        constructorLinkName: String,
        externalLinkPrefix: String
    ) {
        let atomicRefSymbol = ensureClassSymbol(
            named: "AtomicReference",
            in: ownerPackage,
            symbols: symbols,
            interner: interner
        )
        if ownerPackageSymbol != .invalid {
            symbols.setParentSymbol(ownerPackageSymbol, for: atomicRefSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = ownerPackage + [interner.intern("AtomicReference"), typeParamName]
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
        let atomicRefType = types.make(.classType(ClassType(
            classSymbol: atomicRefSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: atomicRefSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: atomicRefSymbol)
        symbols.setPropertyType(atomicRefType, for: atomicRefSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            externalLinkName: constructorLinkName,
            paramType: typeParamType,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicRefSymbol,
            valueType: typeParamType,
            getterLinkName: "\(externalLinkPrefix)_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: typeParamType,
            boolType: types.make(.primitive(.boolean, .nonNull)),
            unitType: types.unitType,
            prefix: externalLinkPrefix,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            includeGetAndSetAlias: true,
            includeCompareAndSet: false,
            symbols: symbols,
            interner: interner
        )
    }
}
