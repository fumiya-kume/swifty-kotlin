import Foundation

/// Synthetic stdlib stubs for kotlin.concurrent.AtomicInt, AtomicLong, AtomicReference,
/// and kotlin.concurrent.atomics.AtomicIntArray.
/// Registers constructors, load/store/exchange/compareAndSet/compareAndExchange methods,
/// arithmetic methods (AtomicInt/AtomicLong), and the `value` / array access properties.
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
            parameters: [(name: "initial", type: intType)],
            symbols: symbols,
            interner: interner
        )

        registerAtomicProperty(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            propertyName: "value",
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
            parameters: [(name: "initial", type: longType)],
            symbols: symbols,
            interner: interner
        )

        registerAtomicProperty(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            propertyName: "value",
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
            parameters: [(name: "initial", type: anyNullableType)],
            symbols: symbols,
            interner: interner
        )

        registerAtomicProperty(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            propertyName: "value",
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
            parameters: [(name: "initial", type: boolType)],
            symbols: symbols,
            interner: interner
        )

        registerAtomicProperty(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            propertyName: "value",
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

        // -- AtomicIntArray --
        let atomicIntArraySymbol = ensureClassSymbol(
            named: "AtomicIntArray",
            in: atomicsPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicIntArrayType = types.make(.classType(ClassType(
            classSymbol: atomicIntArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicIntArrayType, for: atomicIntArraySymbol)
        let intArrayType = primitiveArrayType(
            named: "IntArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicIntArrayStubs(
            packageFQName: atomicsPkg,
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            intArrayType: intArrayType,
            intType: intType,
            boolType: boolType,
            unitType: unitType,
            symbols: symbols,
            interner: interner,
            types: types
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
        parameters: [(name: String, type: TypeID)],
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
            return sig.parameterTypes == parameters.map(\.type)
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

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: ctorFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerAtomicProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        propertyName: String,
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

    private func registerAtomicTopLevelFunction(
        packageFQName: [InternedString],
        name: String,
        externalLinkName: String,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
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
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerAtomicIntArrayStubs(
        packageFQName: [InternedString],
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        intArrayType: TypeID,
        intType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let transformType = types.make(.functionType(FunctionType(
            params: [intType],
            returnType: intType,
            isSuspend: false,
            nullability: .nonNull
        )))

        registerAtomicTopLevelFunction(
            packageFQName: packageFQName,
            name: "AtomicIntArray",
            externalLinkName: "kk_atomic_int_array_create",
            parameters: [
                (name: "size", type: intType),
                (name: "init", type: transformType),
            ],
            returnType: ownerType,
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )

        registerAtomicConstructor(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            externalLinkName: "kk_atomic_int_array_new",
            parameters: [(name: "size", type: intType)],
            symbols: symbols,
            interner: interner
        )
        registerAtomicConstructor(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            externalLinkName: "kk_atomic_int_array_fromArray",
            parameters: [(name: "array", type: intArrayType)],
            symbols: symbols,
            interner: interner
        )

        registerAtomicProperty(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: intType,
            propertyName: "size",
            getterLinkName: "kk_atomic_int_array_size",
            symbols: symbols,
            interner: interner
        )
        registerAtomicProperty(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: intType,
            propertyName: "length",
            getterLinkName: "kk_atomic_int_array_size",
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "loadAt",
            externalLinkName: "kk_atomic_int_array_loadAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "get",
            externalLinkName: "kk_atomic_int_array_loadAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .operatorFunction, .throwingFunction],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "storeAt",
            externalLinkName: "kk_atomic_int_array_storeAt",
            returnType: unitType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: intType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "set",
            externalLinkName: "kk_atomic_int_array_storeAt",
            returnType: unitType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: intType),
            ],
            flags: [.synthetic, .operatorFunction, .throwingFunction],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "exchangeAt",
            externalLinkName: "kk_atomic_int_array_exchangeAt",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: intType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndSet",
            externalLinkName: "kk_atomic_int_array_exchangeAt",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: intType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSetAt",
            externalLinkName: "kk_atomic_int_array_compareAndSetAt",
            returnType: boolType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: intType),
                (name: "newValue", type: intType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndExchangeAt",
            externalLinkName: "kk_atomic_int_array_compareAndExchangeAt",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: intType),
                (name: "newValue", type: intType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "fetchAndAddAt",
            externalLinkName: "kk_atomic_int_array_fetchAndAddAt",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "delta", type: intType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndAdd",
            externalLinkName: "kk_atomic_int_array_fetchAndAddAt",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "delta", type: intType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "addAndFetchAt",
            externalLinkName: "kk_atomic_int_array_addAndFetchAt",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "delta", type: intType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "fetchAndIncrementAt",
            externalLinkName: "kk_atomic_int_array_fetchAndIncrementAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndIncrement",
            externalLinkName: "kk_atomic_int_array_fetchAndIncrementAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "incrementAndFetchAt",
            externalLinkName: "kk_atomic_int_array_incrementAndFetchAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "incrementAndGet",
            externalLinkName: "kk_atomic_int_array_incrementAndFetchAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "fetchAndDecrementAt",
            externalLinkName: "kk_atomic_int_array_fetchAndDecrementAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndDecrement",
            externalLinkName: "kk_atomic_int_array_fetchAndDecrementAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "decrementAndFetchAt",
            externalLinkName: "kk_atomic_int_array_decrementAndFetchAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "decrementAndGet",
            externalLinkName: "kk_atomic_int_array_decrementAndFetchAt",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "fetchAndUpdateAt",
            externalLinkName: "kk_atomic_int_array_fetchAndUpdateAt",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "transform", type: transformType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "updateAndFetchAt",
            externalLinkName: "kk_atomic_int_array_updateAndFetchAt",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "transform", type: transformType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "updateAt",
            externalLinkName: "kk_atomic_int_array_updateAt",
            returnType: unitType,
            parameters: [
                (name: "index", type: intType),
                (name: "transform", type: transformType),
            ],
            flags: [.synthetic, .throwingFunction],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "toString",
            externalLinkName: "kk_atomic_int_array_toString",
            returnType: types.stringType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        flags: SymbolFlags = [.synthetic],
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
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func primitiveArrayType(
        named name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard let symbol = symbols.lookupByShortName(interner.intern(name)).first else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
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
