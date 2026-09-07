
/// Array-shaped atomic surfaces (`AtomicIntArray`/`AtomicLongArray`/
/// `AtomicArray<T>`) and their `atomicArrayOf`/`atomicArrayOfNulls`
/// factories, extracted from the Atomic residual registration surface.
extension DataFlowSemaPhase {
    func registerAtomicArrayFamily(
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
            paramType: types.intType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicReadOnlyProperty(
            ownerSymbol: symbol,
            propertyName: "size",
            valueType: types.intType,
            getterLinkName: "\(prefix)_size",
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "loadAt",
            externalLinkName: "\(prefix)_loadAt",
            returnType: valueType,
            parameters: [(name: "index", type: types.intType)],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "storeAt",
            externalLinkName: "\(prefix)_storeAt",
            returnType: unitType,
            parameters: [(name: "index", type: types.intType), (name: "value", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "get",
            externalLinkName: "\(prefix)_loadAt",
            returnType: valueType,
            parameters: [(name: "index", type: types.intType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "set",
            externalLinkName: "\(prefix)_storeAt",
            returnType: unitType,
            parameters: [(name: "index", type: types.intType), (name: "value", type: valueType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "exchangeAt",
            externalLinkName: "\(prefix)_exchangeAt",
            returnType: valueType,
            parameters: [(name: "index", type: types.intType), (name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        if includeGetAndSetAlias {
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "getAndSet",
                externalLinkName: "\(prefix)_exchangeAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType), (name: "newValue", type: valueType)],
                symbols: symbols,
                interner: interner
            )
        }
        registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "compareAndSetAt",
                externalLinkName: "\(prefix)_compareAndSetAt",
                returnType: boolType,
                parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "compareAndExchangeAt",
                externalLinkName: "\(prefix)_compareAndExchangeAt",
                returnType: valueType,
                parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            symbols: symbols,
            interner: interner
        )

        if includeArithmetic {
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "fetchAndAddAt",
                externalLinkName: "\(prefix)_fetchAndAddAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType), (name: "delta", type: valueType)],
                symbols: symbols,
                interner: interner
            )
            if includeGetAndAddAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "getAndAdd",
                    externalLinkName: "\(prefix)_fetchAndAddAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType), (name: "delta", type: valueType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            if includeIncrementAndGetAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "incrementAndGet",
                    externalLinkName: "\(prefix)_incrementAndFetchAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            if includeGetAndIncrementAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "getAndIncrement",
                    externalLinkName: "\(prefix)_fetchAndIncrementAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            if includeGetAndDecrementAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "getAndDecrement",
                    externalLinkName: "\(prefix)_fetchAndDecrementAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            if includeDecrementAndGetAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "decrementAndGet",
                    externalLinkName: "\(prefix)_decrementAndFetchAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "addAndFetchAt",
                externalLinkName: "\(prefix)_addAndFetchAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType), (name: "delta", type: valueType)],
                symbols: symbols,
                interner: interner
            )
            if includeAddAndGetAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "addAndGet",
                    externalLinkName: "\(prefix)_addAndFetchAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType), (name: "delta", type: valueType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "fetchAndIncrementAt",
                externalLinkName: "\(prefix)_fetchAndIncrementAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType)],
                symbols: symbols,
                interner: interner
            )
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "fetchAndDecrementAt",
                externalLinkName: "\(prefix)_fetchAndDecrementAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType)],
                symbols: symbols,
                interner: interner
            )
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "incrementAndFetchAt",
                externalLinkName: "\(prefix)_incrementAndFetchAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType)],
                symbols: symbols,
                interner: interner
            )
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "decrementAndFetchAt",
                externalLinkName: "\(prefix)_decrementAndFetchAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType)],
                symbols: symbols,
                interner: interner
            )
        }
    }

    /// Registers `kotlin.concurrent.atomics.AtomicArray<T>` backed by
    /// `kk_atomic_ref_array_*` ABI functions.  CAS uses identity semantics.
    func registerAtomicRefArrayStub(
        packageFQName: [InternedString],
        boolType: TypeID,
        unitType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let className = interner.intern("AtomicArray")
        let symbol = ensureClassSymbol(
            named: "AtomicArray",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )

        let typeParamName = interner.intern("T")
        let typeParamFQName = packageFQName + [className, typeParamName]
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
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nullable)))
        let ownerType = types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: symbol)
        types.setNominalTypeParameterVariances([.invariant], for: symbol)
        symbols.setPropertyType(ownerType, for: symbol)

        // constructor(size: Int)
        registerAtomicConstructor(
            ownerSymbol: symbol,
            ownerType: ownerType,
            externalLinkName: "kk_atomic_ref_array_new",
            paramType: types.intType,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // size: Int
        registerAtomicReadOnlyProperty(
            ownerSymbol: symbol,
            propertyName: "size",
            valueType: types.intType,
            getterLinkName: "kk_atomic_ref_array_size",
            symbols: symbols,
            interner: interner
        )

        // loadAt(index: Int): T
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "loadAt",
            externalLinkName: "kk_atomic_ref_array_loadAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // storeAt(index: Int, value: T): Unit
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "storeAt",
            externalLinkName: "kk_atomic_ref_array_storeAt",
            returnType: unitType,
            parameters: [(name: "index", type: types.intType), (name: "value", type: typeParamType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // exchangeAt(index: Int, newValue: T): T
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "exchangeAt",
            externalLinkName: "kk_atomic_ref_array_exchangeAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType), (name: "newValue", type: typeParamType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "getAndSet",
            externalLinkName: "kk_atomic_ref_array_exchangeAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType), (name: "newValue", type: typeParamType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // compareAndSetAt(index: Int, expect: T, update: T): Boolean
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "compareAndSetAt",
            externalLinkName: "kk_atomic_ref_array_compareAndSetAt",
            returnType: boolType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: typeParamType),
                (name: "update", type: typeParamType),
            ],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // compareAndExchangeAt(index: Int, expect: T, update: T): T
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "compareAndExchangeAt",
            externalLinkName: "kk_atomic_ref_array_compareAndExchangeAt",
            returnType: typeParamType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: typeParamType),
                (name: "update", type: typeParamType),
            ],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // get operator alias (index: Int): T
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "get",
            externalLinkName: "kk_atomic_ref_array_loadAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )

        // set operator alias (index: Int, value: T): Unit
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "set",
            externalLinkName: "kk_atomic_ref_array_storeAt",
            returnType: unitType,
            parameters: [(name: "index", type: types.intType), (name: "value", type: typeParamType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
    }

    func registerAtomicArrayOfNullsFactory(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let functionName = interner.intern("atomicArrayOfNulls")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes == [types.intType]
                && signature.typeParameterSymbols.count == 1
        }) {
            symbols.setExternalLinkName("kk_atomic_ref_array_new", for: existing)
            return
        }

        guard let atomicArraySymbol = symbols.lookup(fqName: packageFQName + [interner.intern("AtomicArray")]) else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_atomic_ref_array_new", for: functionSymbol)

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nullable)))
        let returnType = types.make(.classType(ClassType(
            classSymbol: atomicArraySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        let sizeName = interner.intern("size")
        let sizeSymbol = symbols.define(
            kind: .valueParameter,
            name: sizeName,
            fqName: functionFQName + [sizeName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: sizeSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [types.intType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [sizeSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    func registerAtomicArrayOfFactory(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let functionName = interner.intern("atomicArrayOf")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 1
                && signature.valueParameterIsVararg.first == true
        }) {
            symbols.setExternalLinkName("kk_atomic_ref_array_of", for: existing)
            return
        }

        guard let atomicArraySymbol = symbols.lookup(fqName: packageFQName + [interner.intern("AtomicArray")]) else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_atomic_ref_array_of", for: functionSymbol)

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nonNull)))
        let returnType = types.make(.classType(ClassType(
            classSymbol: atomicArraySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [typeParamType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
