import Foundation

/// Synthetic stdlib stubs for kotlin.concurrent atomic and lock types.
/// Registers constructors, load/store/exchange/compareAndSet/compareAndExchange methods,
/// arithmetic methods (AtomicInt/AtomicLong), and the `value` property.
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

        // -- ReentrantReadWriteLock --
        let rwLockSymbol = ensureClassSymbol(
            named: "ReentrantReadWriteLock",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let rwLockType = types.make(.classType(ClassType(
            classSymbol: rwLockSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(rwLockType, for: rwLockSymbol)

        registerReadWriteLockConstructor(
            ownerSymbol: rwLockSymbol,
            ownerType: rwLockType,
            externalLinkName: "kk_read_write_lock_create",
            symbols: symbols,
            interner: interner
        )

        let readWriteActionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerAtomicMember(
            ownerSymbol: rwLockSymbol,
            ownerType: rwLockType,
            name: "read",
            externalLinkName: "kk_read_write_lock_read",
            returnType: types.anyType,
            parameters: [(
                name: "action",
                type: readWriteActionType
            )],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: rwLockSymbol,
            ownerType: rwLockType,
            name: "write",
            externalLinkName: "kk_read_write_lock_write",
            returnType: types.anyType,
            parameters: [(
                name: "action",
                type: readWriteActionType
            )],
            symbols: symbols,
            interner: interner
        )

        registerReadWriteLockFactory(
            packageFQName: concurrentPkg,
            returnType: rwLockType,
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

        let paramName = interner.intern("initial")
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
                valueParameterIsVararg: [false]
            ),
            for: ctorSymbol
        )
    }

    private func registerReadWriteLockConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        if let existing = symbols.lookupAll(fqName: ctorFQName).first(where: { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .constructor,
                  let sig = symbols.functionSignature(for: id)
            else { return false }
            return sig.parameterTypes.isEmpty
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

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
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: ownerType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: ctorSymbol
        )
    }

    private func registerAtomicValueProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        getterLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern("value")
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
        }) {
            symbols.setExternalLinkName(getterLinkName, for: existing)
            symbols.setPropertyType(valueType, for: existing)
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
            flags: [.synthetic]
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

    private func registerReadWriteLockFactory(
        packageFQName: [InternedString],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern("readWriteLock")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes.isEmpty
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName("kk_read_write_lock_create", for: existing)
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
        symbols.setExternalLinkName("kk_read_write_lock_create", for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
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
