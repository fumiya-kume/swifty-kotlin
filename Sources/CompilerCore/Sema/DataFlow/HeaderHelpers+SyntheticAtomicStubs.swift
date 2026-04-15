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
        let atomicsPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent", "atomics"],
            symbols: symbols,
            interner: interner
        )

        let intType = types.intType
        let longType = types.longType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let unitType = types.unitType

        registerAtomicScalarFamily(
            packageFQName: concurrentPkg,
            className: "AtomicInt",
            constructorLinkName: "kk_atomic_int_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int",
            includeArithmetic: true,
            includeGetAndUpdate: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicScalarFamily(
            packageFQName: concurrentPkg,
            className: "AtomicLong",
            constructorLinkName: "kk_atomic_long_create",
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long",
            includeArithmetic: true,
            includeGetAndUpdate: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicScalarFamily(
            packageFQName: concurrentPkg,
            className: "AtomicBoolean",
            constructorLinkName: "kk_atomic_bool_create",
            valueType: boolType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_bool",
            includeArithmetic: false,
            includeGetAndUpdate: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicReferenceStubs(
            ownerPackage: concurrentPkg,
            ownerPackageSymbol: symbols.lookup(fqName: concurrentPkg) ?? .invalid,
            symbols: symbols,
            types: types,
            interner: interner,
            externalLinkPrefix: "kk_atomic_ref"
        )

        registerSyntheticAtomicAnnotation(
            named: "ExperimentalAtomicApi",
            in: atomicsPkg,
            symbols: symbols,
            interner: interner
        )
        let memoryOrderSymbol = ensureAtomicMemoryOrderEnum(
            in: atomicsPkg,
            symbols: symbols,
            interner: interner
        )
        let memoryOrderType = types.make(.classType(ClassType(
            classSymbol: memoryOrderSymbol,
            args: [],
            nullability: .nonNull
        )))
        setAtomicEnumEntryTypes(
            enumSymbol: memoryOrderSymbol,
            enumType: memoryOrderType,
            symbols: symbols
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicInt",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicInt",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicLong",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicLong",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicBoolean",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicBoolean",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicReference",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicReference",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types,
            typeParameterNames: ["T"]
        )

        registerAtomicArrayFamily(
            packageFQName: atomicsPkg,
            className: "AtomicIntArray",
            constructorLinkName: "kk_atomic_int_array_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int_array",
            includeArithmetic: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicArrayFamily(
            packageFQName: atomicsPkg,
            className: "AtomicLongArray",
            constructorLinkName: "kk_atomic_long_array_create",
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long_array",
            includeArithmetic: true,
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

    private func ensureAtomicMemoryOrderEnum(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("MemoryOrder")
        let fqName = pkg + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        let symbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: symbol)
        }

        let entries = [
            "RELAXED",
            "ACQUIRE",
            "RELEASE",
            "ACQUIRE_RELEASE",
            "SEQUENTIALLY_CONSISTENT",
        ]
        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(symbol, for: entrySymbol)
        }
        return symbol
    }

    private func setAtomicEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let children = symbols.children(ofFQName: enumInfo.fqName)
        for child in children {
            guard let childSym = symbols.symbol(child),
                  childSym.kind == .field
            else {
                continue
            }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }

    private func registerAtomicScalarFamily(
        packageFQName: [InternedString],
        className: String,
        constructorLinkName: String,
        valueType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        includeArithmetic: Bool,
        includeGetAndUpdate: Bool,
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
            ownerType: ownerType,
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
            symbols: symbols,
            interner: interner
        )

        if includeArithmetic {
            registerAtomicArithmeticMethods(
                ownerSymbol: symbol,
                ownerType: ownerType,
                valueType: valueType,
                prefix: prefix,
                symbols: symbols,
                interner: interner
            )
        }

        if includeGetAndUpdate {
            registerAtomicGetAndUpdateMethods(
                ownerSymbol: symbol,
                ownerType: ownerType,
                valueType: valueType,
                prefix: prefix,
                symbols: symbols,
                interner: interner,
                types: types
            )
        }
    }

    private func registerAtomicReferenceFamily(
        packageFQName: [InternedString],
        constructorLinkName: String,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let className = interner.intern("AtomicReference")
        let symbol = ensureClassSymbol(
            named: "AtomicReference",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        let typeParamName = interner.intern("T")
        let typeParamFQName = packageFQName + [className, typeParamName]
        let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nullable)))
        let ownerType = types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: symbol)

        registerAtomicConstructor(
            ownerSymbol: symbol,
            ownerType: ownerType,
            externalLinkName: constructorLinkName,
            paramType: typeParamType,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: symbol,
            ownerType: ownerType,
            valueType: typeParamType,
            getterLinkName: "\(prefix)_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: symbol,
            ownerType: ownerType,
            valueType: typeParamType,
            boolType: boolType,
            unitType: unitType,
            prefix: prefix,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: symbol,
            ownerType: ownerType,
            valueType: typeParamType,
            prefix: prefix,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner,
            types: types
        )
    }

    private func registerAtomicArrayFamily(
        packageFQName: [InternedString],
        className: String,
        constructorLinkName: String,
        valueType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        includeArithmetic: Bool,
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
            ownerType: ownerType,
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

    private func registerSyntheticAtomicAnnotation(
        named name: String,
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let annotationName = interner.intern(name)
        let fqName = packageFQName + [annotationName]
        guard symbols.lookup(fqName: fqName) == nil else { return }

        _ = symbols.define(
            kind: .annotationClass,
            name: annotationName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func registerAtomicTypeAlias(
        aliasName: String,
        aliasPackageFQName: [InternedString],
        targetName: String,
        targetPackageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem,
        typeParameterNames: [String] = []
    ) {
        let aliasInterned = interner.intern(aliasName)
        let aliasFQName = aliasPackageFQName + [aliasInterned]
        guard symbols.lookup(fqName: aliasFQName) == nil else { return }

        let targetInterned = interner.intern(targetName)
        let targetFQName = targetPackageFQName + [targetInterned]
        guard let targetSymbol = symbols.lookup(fqName: targetFQName) else { return }

        let aliasSymbol = symbols.define(
            kind: .typeAlias,
            name: aliasInterned,
            fqName: aliasFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let underlyingArgs: [TypeArg]
        if typeParameterNames.isEmpty {
            underlyingArgs = []
        } else {
            let typeParamSymbols = typeParameterNames.map { paramName in
                let internedParam = interner.intern(paramName)
                let typeParamFQName = aliasFQName + [internedParam]
                return symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
                    kind: .typeParameter,
                    name: internedParam,
                    fqName: typeParamFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            symbols.setTypeAliasTypeParameters(typeParamSymbols, for: aliasSymbol)
            underlyingArgs = typeParamSymbols.map { typeParamSymbol in
                .invariant(types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nullable))))
            }
        }
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: underlyingArgs,
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    private func registerAtomicConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        paramType: TypeID,
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

    private func registerAtomicReadOnlyProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        propertyName: String,
        valueType: TypeID,
        getterLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(propertyName)
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
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // load() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "load", externalLinkName: "\(prefix)_load",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // store(value: T) -> Unit (returns via side effect)
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "store", externalLinkName: "\(prefix)_store",
            returnType: unitType, parameters: [(name: "value", type: valueType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // exchange(new: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "exchange", externalLinkName: "\(prefix)_exchange",
            returnType: valueType, parameters: [(name: "new", type: valueType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
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
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
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
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicArithmeticMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
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
        // addAndFetch(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "addAndFetch", externalLinkName: "\(prefix)_addAndFetch",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // fetchAndIncrement() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndIncrement", externalLinkName: "\(prefix)_fetchAndIncrement",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // incrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "incrementAndFetch", externalLinkName: "\(prefix)_incrementAndFetch",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // decrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "decrementAndFetch", externalLinkName: "\(prefix)_decrementAndFetch",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicGetAndUpdateMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
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
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // updateAndGet(transform: (T) -> T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "updateAndGet", externalLinkName: "\(prefix)_updateAndGet",
            returnType: valueType, parameters: [(name: "transform", type: transformType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicReferenceStubs(
        ownerPackage: [InternedString],
        ownerPackageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
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
            externalLinkName: "\(externalLinkPrefix)_create",
            paramType: typeParamType,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
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
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: typeParamType,
            prefix: externalLinkPrefix,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner,
            types: types
        )
    }

    private func registerAtomicMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
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
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
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

    private func registerSyntheticAnnotationClass(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        if let existing = symbols.lookup(fqName: classFQName) {
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
            return
        }

        let classSymbol = symbols.define(
            kind: .annotationClass,
            name: className,
            fqName: classFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
    }
}
