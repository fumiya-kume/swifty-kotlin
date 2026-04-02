import Foundation

/// Synthetic stdlib stubs for kotlin.concurrent atomic and lock types.
/// Registers constructors, load/store/exchange/compareAndSet/compareAndExchange methods,
/// arithmetic methods (AtomicInt/AtomicLong), the `value` property, and the
/// experimental atomic arrays under `kotlin.concurrent.atomics`.
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

        registerSyntheticAtomicAnnotation(
            named: "ExperimentalAtomicApi",
            packageFQName: atomicsPkg,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueTypes(
            packageFQName: concurrentPkg,
            includeLock: true,
            intType: intType,
            longType: longType,
            boolType: boolType,
            anyNullableType: anyNullableType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerAtomicValueTypes(
            packageFQName: atomicsPkg,
            includeLock: false,
            intType: intType,
            longType: longType,
            boolType: boolType,
            anyNullableType: anyNullableType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerAtomicArrayTypes(
            packageFQName: atomicsPkg,
            intType: intType,
            longType: longType,
            boolType: boolType,
            unitType: unitType,
            symbols: symbols,
            types: types,
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
        canThrow: Bool = false,
        extraFlags: SymbolFlags = [],
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

        var memberFlags: SymbolFlags = [.synthetic]
        if canThrow {
            memberFlags.insert(.throwingFunction)
        }
        memberFlags.formUnion(extraFlags)

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: memberFlags
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

    private func registerAtomicValueTypes(
        packageFQName: [InternedString],
        includeLock: Bool,
        intType: TypeID,
        longType: TypeID,
        boolType: TypeID,
        anyNullableType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let packageSymbol = symbols.lookup(fqName: packageFQName) ?? .invalid

        registerAtomicValueType(
            named: "AtomicInt",
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            constructorLinkName: "kk_atomic_int_create",
            valueType: intType,
            valueGetterLinkName: "kk_atomic_int_load",
            corePrefix: "kk_atomic_int",
            includeArithmeticMethods: true,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerAtomicValueType(
            named: "AtomicLong",
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            constructorLinkName: "kk_atomic_long_create",
            valueType: longType,
            valueGetterLinkName: "kk_atomic_long_load",
            corePrefix: "kk_atomic_long",
            includeArithmeticMethods: true,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerAtomicValueType(
            named: "AtomicReference",
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            constructorLinkName: "kk_atomic_ref_create",
            valueType: anyNullableType,
            valueGetterLinkName: "kk_atomic_ref_load",
            corePrefix: "kk_atomic_ref",
            includeArithmeticMethods: false,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerAtomicValueType(
            named: "AtomicBoolean",
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            constructorLinkName: "kk_atomic_bool_create",
            valueType: boolType,
            valueGetterLinkName: "kk_atomic_bool_load",
            corePrefix: "kk_atomic_bool",
            includeArithmeticMethods: false,
            symbols: symbols,
            types: types,
            interner: interner
        )

        if includeLock {
            let lockSymbol = ensureClassSymbol(
                named: "Lock",
                in: packageFQName,
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
    }

    private func registerAtomicValueType(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        constructorLinkName: String,
        valueType: TypeID,
        valueGetterLinkName: String,
        corePrefix: String,
        includeArithmeticMethods: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let ownerSymbol = ensureSyntheticNominalType(
            named: name,
            kind: .class,
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        )
        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: ownerSymbol)

        registerAtomicConstructor(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            externalLinkName: constructorLinkName,
            paramType: valueType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: valueType,
            getterLinkName: valueGetterLinkName,
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: valueType,
            boolType: types.make(.primitive(.boolean, .nonNull)),
            unitType: types.unitType,
            prefix: corePrefix,
            symbols: symbols,
            interner: interner
        )

        if includeArithmeticMethods {
            registerAtomicArithmeticMethods(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                valueType: valueType,
                prefix: corePrefix,
                symbols: symbols,
                interner: interner
            )
        }

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: valueType,
            prefix: corePrefix,
            symbols: symbols,
            interner: interner,
            types: types
        )
    }

    private func registerAtomicArrayTypes(
        packageFQName: [InternedString],
        intType: TypeID,
        longType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let packageSymbol = symbols.lookup(fqName: packageFQName) ?? .invalid
        registerAtomicArrayType(
            named: "AtomicIntArray",
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            valueType: intType,
            sizeType: intType,
            createLinkName: "kk_atomic_int_array_create",
            sizeLinkName: "kk_atomic_int_array_size",
            getLinkName: "kk_atomic_int_array_get",
            setLinkName: "kk_atomic_int_array_set",
            compareAndSetLinkName: "kk_atomic_int_array_compareAndSet",
            getAndAddLinkName: "kk_atomic_int_array_getAndAdd",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicArrayType(
            named: "AtomicLongArray",
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            valueType: longType,
            sizeType: intType,
            createLinkName: "kk_atomic_long_array_create",
            sizeLinkName: "kk_atomic_long_array_size",
            getLinkName: "kk_atomic_long_array_get",
            setLinkName: "kk_atomic_long_array_set",
            compareAndSetLinkName: "kk_atomic_long_array_compareAndSet",
            getAndAddLinkName: "kk_atomic_long_array_getAndAdd",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerAtomicArrayType(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        valueType: TypeID,
        sizeType: TypeID,
        createLinkName: String,
        sizeLinkName: String,
        getLinkName: String,
        setLinkName: String,
        compareAndSetLinkName: String,
        getAndAddLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
        ) {
        let ownerSymbol = ensureSyntheticNominalType(
            named: name,
            kind: .class,
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        )
        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: ownerSymbol)
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let unitType = types.unitType

        registerAtomicArrayConstructor(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            sizeType: sizeType,
            externalLinkName: createLinkName,
            symbols: symbols,
            interner: interner
        )

        registerAtomicArraySizeProperty(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            sizeType: sizeType,
            externalLinkName: sizeLinkName,
            symbols: symbols,
            interner: interner
        )

        let operatorFlags: SymbolFlags = [.operatorFunction]
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "get",
            externalLinkName: getLinkName,
            returnType: valueType,
            parameters: [(name: "index", type: sizeType)],
            canThrow: true,
            extraFlags: operatorFlags,
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "set",
            externalLinkName: setLinkName,
            returnType: unitType,
            parameters: [
                (name: "index", type: sizeType),
                (name: "value", type: valueType),
            ],
            canThrow: true,
            extraFlags: operatorFlags,
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSet",
            externalLinkName: compareAndSetLinkName,
            returnType: boolType,
            parameters: [
                (name: "index", type: sizeType),
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndAdd",
            externalLinkName: getAndAddLinkName,
            returnType: valueType,
            parameters: [
                (name: "index", type: sizeType),
                (name: "delta", type: valueType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicArrayConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        sizeType: TypeID,
        externalLinkName: String,
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
            return sig.parameterTypes == [sizeType]
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

        let paramName = interner.intern("size")
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
                parameterTypes: [sizeType],
                returnType: ownerType,
                valueParameterSymbols: [paramSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: ctorSymbol
        )
    }

    private func registerAtomicArraySizeProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        sizeType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern("size")
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(sizeType, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(sizeType, for: propertySymbol)
    }

    private func registerSyntheticAnnotationClass(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        _ = ensureSyntheticNominalType(
            named: name,
            kind: .annotationClass,
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticAtomicAnnotation(
        named name: String,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let packageSymbol = symbols.lookup(fqName: packageFQName) ?? .invalid
        registerSyntheticAnnotationClass(
            named: name,
            packageFQName: packageFQName,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        )
        if let annotationSymbol = symbols.lookup(fqName: packageFQName + [interner.intern(name)]) {
            let record = MetadataAnnotationRecord(annotationFQName: "kotlin.WasExperimental")
            var annotations = symbols.annotations(for: annotationSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
                symbols.setAnnotations(annotations, for: annotationSymbol)
            }
        }
    }

    private func ensureSyntheticNominalType(
        named name: String,
        kind: SymbolKind,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let typeName = interner.intern(name)
        let typeFQName = packageFQName + [typeName]
        if let existing = symbols.lookup(fqName: typeFQName) {
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
            return existing
        }

        let typeSymbol = symbols.define(
            kind: kind,
            name: typeName,
            fqName: typeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: typeSymbol)
        }
        return typeSymbol
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
