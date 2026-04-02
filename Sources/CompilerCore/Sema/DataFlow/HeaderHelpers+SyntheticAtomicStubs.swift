import Foundation

/// Synthetic stdlib stubs for kotlin.concurrent.AtomicInt, AtomicLong, AtomicReference,
/// kotlin.concurrent.atomics.AtomicArray, and kotlin.concurrent lock types.
/// Registers constructors, load/store/exchange/compareAndSet/compareAndExchange methods,
/// arithmetic methods (AtomicInt/AtomicLong), AtomicArray indexed operations,
/// and the relevant properties / factory functions.
extension DataFlowSemaPhase {
    func registerSyntheticAtomicStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let concurrentPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let atomicsPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent", "atomics"],
            symbols: symbols,
            interner: interner
        )

        let intType = types.intType
        let longType = types.longType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyNullableType = types.make(.any(.nullable))
        let unitType = types.unitType

        // -- AtomicInt --
        let atomicIntSymbol = ensureClassSymbol(
            named: "AtomicInt",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicIntType = types.make(.classType(ClassType(
            classSymbol: atomicIntSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicIntType, for: atomicIntSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            externalLinkName: "kk_atomic_int_create",
            paramType: intType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            getterLinkName: "kk_atomic_int_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner
        )

        registerAtomicArithmeticMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner
        )
        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicLong --
        let atomicLongSymbol = ensureClassSymbol(
            named: "AtomicLong",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicLongType = types.make(.classType(ClassType(
            classSymbol: atomicLongSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicLongType, for: atomicLongSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            externalLinkName: "kk_atomic_long_create",
            paramType: longType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            getterLinkName: "kk_atomic_long_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner
        )

        registerAtomicArithmeticMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner
        )
        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicReference<T> --
        let atomicRefSymbol = ensureClassSymbol(
            named: "AtomicReference",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicRefType = types.make(.classType(ClassType(
            classSymbol: atomicRefSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicRefType, for: atomicRefSymbol)

        // AtomicReference stores values as Any? at the ABI level.
        registerAtomicConstructor(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            externalLinkName: "kk_atomic_ref_create",
            paramType: anyNullableType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            getterLinkName: "kk_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_ref",
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            prefix: "kk_atomic_ref",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicBoolean --
        let atomicBoolSymbol = ensureClassSymbol(
            named: "AtomicBoolean",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicBoolType = types.make(.classType(ClassType(
            classSymbol: atomicBoolSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicBoolType, for: atomicBoolSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            externalLinkName: "kk_atomic_bool_create",
            paramType: boolType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            getterLinkName: "kk_atomic_bool_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_bool",
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            prefix: "kk_atomic_bool",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicArray<T> --
        let atomicArraySymbol = ensureClassSymbol(
            named: "AtomicArray",
            in: atomicsPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicArrayTypeParamName = interner.intern("T")
        let atomicArrayTypeParamFQName = atomicsPkg + [interner.intern("AtomicArray"), atomicArrayTypeParamName]
        let atomicArrayTypeParamSymbol = symbols.lookup(fqName: atomicArrayTypeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: atomicArrayTypeParamName,
            fqName: atomicArrayTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let atomicArrayTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: atomicArrayTypeParamSymbol,
            nullability: .nonNull
        )))
        let atomicArrayType = types.make(.classType(ClassType(
            classSymbol: atomicArraySymbol,
            args: [.invariant(atomicArrayTypeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicArrayType, for: atomicArraySymbol)
        types.setNominalTypeParameterSymbols([atomicArrayTypeParamSymbol], for: atomicArraySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: atomicArraySymbol)

        // Constructor: AtomicArray(array: Array<T>)
        let arrayFQName = [interner.intern("kotlin"), interner.intern("Array")]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return
        }
        let sourceArrayType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(atomicArrayTypeParamType)],
            nullability: .nonNull
        )))
        registerAtomicConstructor(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            externalLinkName: "kk_atomic_array_create",
            paramType: sourceArrayType,
            parameterName: "array",
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            propertyName: "size",
            valueType: types.intType,
            getterLinkName: "kk_atomic_array_size",
            symbols: symbols,
            interner: interner
        )

        // Factory: AtomicArray(size: Int, init: (Int) -> T)
        let factoryTypeParamName = interner.intern("T")
        let factoryTypeParamFQName = atomicsPkg + [interner.intern("AtomicArray"), factoryTypeParamName, interner.intern("$synthetic")]
        let factoryTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: factoryTypeParamName,
            fqName: factoryTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let factoryTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: factoryTypeParamSymbol,
            nullability: .nonNull
        )))
        let factoryInitType = types.make(.functionType(FunctionType(
            params: [types.intType],
            returnType: factoryTypeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let factoryReturnType = types.make(.classType(ClassType(
            classSymbol: atomicArraySymbol,
            args: [.invariant(factoryTypeParamType)],
            nullability: .nonNull
        )))
        registerAtomicTopLevelFunction(
            named: "AtomicArray",
            packageFQName: atomicsPkg,
            externalLinkName: "kk_atomic_array_new",
            parameters: [
                (name: "size", type: types.intType),
                (name: "init", type: factoryInitType),
            ],
            returnType: factoryReturnType,
            typeParameterSymbols: [factoryTypeParamSymbol],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        // Factory: atomicArrayOfNulls<T>(size: Int)
        let ofNullsTypeParamName = interner.intern("T")
        let ofNullsTypeParamFQName = atomicsPkg + [interner.intern("atomicArrayOfNulls"), ofNullsTypeParamName]
        let ofNullsTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: ofNullsTypeParamName,
            fqName: ofNullsTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let ofNullsTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: ofNullsTypeParamSymbol,
            nullability: .nonNull
        )))
        let ofNullsReturnType = types.make(.classType(ClassType(
            classSymbol: atomicArraySymbol,
            args: [.invariant(types.makeNullable(ofNullsTypeParamType))],
            nullability: .nonNull
        )))
        registerAtomicTopLevelFunction(
            named: "atomicArrayOfNulls",
            packageFQName: atomicsPkg,
            externalLinkName: "kk_atomic_array_ofNulls",
            parameters: [
                (name: "size", type: types.intType),
            ],
            returnType: ofNullsReturnType,
            typeParameterSymbols: [ofNullsTypeParamSymbol],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            name: "loadAt",
            externalLinkName: "kk_atomic_array_loadAt",
            returnType: atomicArrayTypeParamType,
            parameters: [(name: "index", type: types.intType)],
            canThrow: true,
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            name: "storeAt",
            externalLinkName: "kk_atomic_array_storeAt",
            returnType: unitType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "value", type: atomicArrayTypeParamType),
            ],
            canThrow: true,
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            name: "exchangeAt",
            externalLinkName: "kk_atomic_array_exchangeAt",
            returnType: atomicArrayTypeParamType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "new", type: atomicArrayTypeParamType),
            ],
            canThrow: true,
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            name: "compareAndSetAt",
            externalLinkName: "kk_atomic_array_compareAndSetAt",
            returnType: boolType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: atomicArrayTypeParamType),
                (name: "update", type: atomicArrayTypeParamType),
            ],
            canThrow: true,
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            name: "compareAndExchangeAt",
            externalLinkName: "kk_atomic_array_compareAndExchangeAt",
            returnType: atomicArrayTypeParamType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: atomicArrayTypeParamType),
                (name: "update", type: atomicArrayTypeParamType),
            ],
            canThrow: true,
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        let atomicArrayTransformType = types.make(.functionType(FunctionType(
            params: [atomicArrayTypeParamType],
            returnType: atomicArrayTypeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))

        registerAtomicMember(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            name: "fetchAndUpdateAt",
            externalLinkName: "kk_atomic_array_fetchAndUpdateAt",
            returnType: atomicArrayTypeParamType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "updateFn", type: atomicArrayTransformType),
            ],
            canThrow: true,
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            name: "updateAndFetchAt",
            externalLinkName: "kk_atomic_array_updateAndFetchAt",
            returnType: atomicArrayTypeParamType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "updateFn", type: atomicArrayTransformType),
            ],
            canThrow: true,
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            name: "updateAt",
            externalLinkName: "kk_atomic_array_updateAt",
            returnType: unitType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "updateFn", type: atomicArrayTransformType),
            ],
            canThrow: true,
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicArraySymbol,
            ownerType: atomicArrayType,
            name: "toString",
            externalLinkName: "kk_atomic_array_toString",
            returnType: types.stringType,
            parameters: [],
            typeParameterSymbols: [atomicArrayTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // -- Lock --
        let lockSymbol = ensureClassSymbol(
            named: "Lock",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let lockType = types.make(.classType(ClassType(
            classSymbol: lockSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(lockType, for: lockSymbol)
        registerAtomicMember(
            ownerSymbol: lockSymbol,
            ownerType: lockType,
            name: "withLock",
            externalLinkName: "kk_lock_withLock",
            returnType: types.anyType,
            parameters: [(
                name: "action",
                type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            )],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Helpers

    private func registerAtomicConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        paramType: TypeID,
        parameterName: String = "initial",
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatch = symbols.lookupAll(fqName: ctorFQName).contains { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .constructor,
                  let sig = symbols.functionSignature(for: id)
            else { return false }
            return sig.parameterTypes == [paramType]
        }
        guard !hasMatch else { return }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        let paramName = interner.intern(parameterName)
        let paramSymbol = symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: ctorFQName + [paramName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ctorSymbol, for: paramSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [paramType],
                returnType: ownerType,
                valueParameterSymbols: [paramSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: ctorSymbol
        )
    }

    private func registerAtomicValueProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        propertyName: String = "value",
        valueType: TypeID,
        getterLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyNameID = interner.intern(propertyName)
        let propertyFQName = ownerInfo.fqName + [propertyNameID]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
        }) {
            symbols.setExternalLinkName(getterLinkName, for: existing)
            symbols.setPropertyType(valueType, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyNameID,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(getterLinkName, for: propertySymbol)
        symbols.setPropertyType(valueType, for: propertySymbol)
    }

    private func registerAtomicCoreMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // load() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "load", externalLinkName: "\(prefix)_load",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
        // store(value: T) -> Unit (returns via side effect)
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "store", externalLinkName: "\(prefix)_store",
            returnType: unitType, parameters: [(name: "value", type: valueType)],
            symbols: symbols, interner: interner
        )
        // exchange(new: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "exchange", externalLinkName: "\(prefix)_exchange",
            returnType: valueType, parameters: [(name: "new", type: valueType)],
            symbols: symbols, interner: interner
        )
        // compareAndSet(expect: T, update: T) -> Boolean
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "compareAndSet", externalLinkName: "\(prefix)_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            symbols: symbols, interner: interner
        )
        // compareAndExchange(expect: T, update: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "compareAndExchange", externalLinkName: "\(prefix)_compareAndExchange",
            returnType: valueType,
            parameters: [
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicArithmeticMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // fetchAndAdd(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndAdd", externalLinkName: "\(prefix)_fetchAndAdd",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            symbols: symbols, interner: interner
        )
        // addAndFetch(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "addAndFetch", externalLinkName: "\(prefix)_addAndFetch",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            symbols: symbols, interner: interner
        )
        // fetchAndIncrement() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndIncrement", externalLinkName: "\(prefix)_fetchAndIncrement",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
        // incrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "incrementAndFetch", externalLinkName: "\(prefix)_incrementAndFetch",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
        // decrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "decrementAndFetch", externalLinkName: "\(prefix)_decrementAndFetch",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicGetAndUpdateMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let transformType = types.make(.functionType(FunctionType(
            params: [valueType],
            returnType: valueType,
            isSuspend: false,
            nullability: .nonNull
        )))
        // getAndUpdate(transform: (T) -> T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "getAndUpdate", externalLinkName: "\(prefix)_getAndUpdate",
            returnType: valueType, parameters: [(name: "transform", type: transformType)],
            symbols: symbols, interner: interner
        )
        // updateAndGet(transform: (T) -> T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "updateAndGet", externalLinkName: "\(prefix)_updateAndGet",
            returnType: valueType, parameters: [(name: "transform", type: transformType)],
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        canThrow: Bool = false,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { id in
            guard let sig = symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == parameters.map(\.type) &&
                sig.returnType == returnType
        }) == nil else { return }

        var flags: SymbolFlags = [.synthetic]
        if canThrow {
            flags.formUnion([.throwingFunction])
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: memberSymbol
        )
    }

    private func registerAtomicTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        externalLinkName: String,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        typeParameterSymbols: [SymbolID] = [],
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let existingSymbols = symbols.lookupAll(fqName: functionFQName)
        let hasExistingFunctionWithSameArity = existingSymbols.contains { id in
            guard let sym = symbols.symbol(id), sym.kind == .function else { return false }
            let sig = symbols.functionSignature(for: id)
            return sig?.parameterTypes.count == parameters.count
        }
        guard !hasExistingFunctionWithSameArity else {
            return
        }

        var flags: SymbolFlags = [.synthetic]
        if canThrow {
            flags.formUnion([.throwingFunction])
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
    }

    private func ensureAtomicPackage(
        path: [String],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        var fqName: [InternedString] = []
        for component in path {
            let interned = interner.intern(component)
            fqName.append(interned)
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: interned,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return fqName
    }
}
