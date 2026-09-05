
/// Registration entry point for the atomic surfaces that still need synthetic
/// nominal shells or compatibility members. Scalar public APIs live in bundled
/// Kotlin source; arrays, package metadata, NativePtr, and Java compatibility
/// remain registered through the responsibility-specific helpers.
extension DataFlowSemaPhase {
    func registerSyntheticAtomicResidualStubs(
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
            prefix: "__kk_atomic_int",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
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
            prefix: "__kk_atomic_long",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
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
            prefix: "__kk_atomic_bool",
            includeArithmetic: false,
            includeGetAndSetAlias: true,
            includeCompareAndSet: false,
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
            constructorLinkName: "kk_atomic_ref_create",
            externalLinkPrefix: "__kk_atomic_ref"
        )

        // Array atomics retain their responsibility-specific synthetic shells and
        // are intentionally outside KSP-696's scalar migration boundary.
        registerAtomicArrayFamily(
            packageFQName: concurrentPkg,
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
            packageFQName: concurrentPkg,
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
        registerAtomicNativePtrSurface(
            packageFQName: atomicsPkg,
            packageSymbol: symbols.lookup(fqName: atomicsPkg),
            symbols: symbols,
            types: types,
            interner: interner
        )

        // java.util.concurrent.atomic.AtomicInteger is a live compatibility
        // surface backed by the same box as kotlin.concurrent.AtomicInt.
        let javaAtomicPkg = ensureAtomicPackage(
            path: ["java", "util", "concurrent", "atomic"],
            symbols: symbols,
            interner: interner
        )
        registerAtomicScalarFamily(
            packageFQName: javaAtomicPkg,
            className: "AtomicInteger",
            constructorLinkName: "kk_atomic_int_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "__kk_atomic_int",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
            compareAndSetLinkName: "kk_atomic_int_compareAndSet",
            symbols: symbols,
            interner: interner,
            types: types
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
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
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
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicRefArrayStub(
            packageFQName: atomicsPkg,
            boolType: boolType,
            unitType: unitType,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicArrayOfNullsFactory(
            packageFQName: atomicsPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicArrayOfFactory(
            packageFQName: atomicsPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )

        // Lock.withLock is source-backed; retain only its synthetic type shell.
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
    }
}
