import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: AtomicInt / AtomicLong / AtomicNativePtr legacy scalar classes.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - AtomicInt / AtomicLong / AtomicNativePtr

    func registerNativeConcurrentLegacyAtomicScalars(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerNativeConcurrentLegacyAtomicInt(
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentLegacyAtomicLong(
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentLegacyAtomicNativePtr(
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicInt(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let atomicType = registerNativeConcurrentLegacyAtomicClass(
            named: "AtomicInt",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            valueType: types.intType,
            constructorDefault: false,
            replacement: "kotlin.concurrent.atomics.AtomicInt",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ownerSymbol = atomicType.classSymbol
        let ownerType = types.make(.classType(atomicType))
        registerNativeConcurrentAtomicNumericMembers(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: types.intType,
            addAndGetParameterTypes: [types.intType],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicLong(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let atomicType = registerNativeConcurrentLegacyAtomicClass(
            named: "AtomicLong",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            valueType: types.longType,
            constructorDefault: true,
            replacement: "kotlin.concurrent.atomics.AtomicLong",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ownerSymbol = atomicType.classSymbol
        let ownerType = types.make(.classType(atomicType))
        registerNativeConcurrentAtomicNumericMembers(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: types.longType,
            addAndGetParameterTypes: [types.intType, types.longType],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicNativePtr(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePtrType = nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "NativePtr",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let atomicType = registerNativeConcurrentLegacyAtomicClass(
            named: "AtomicNativePtr",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            valueType: nativePtrType,
            constructorDefault: false,
            replacement: "kotlin.concurrent.atomics.AtomicNativePtr",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ownerSymbol = atomicType.classSymbol
        let ownerType = types.make(.classType(atomicType))
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSet",
            returnType: types.booleanType,
            parameters: [
                (name: "expected", type: nativePtrType),
                (name: "newValue", type: nativePtrType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSwap",
            returnType: nativePtrType,
            parameters: [
                (name: "expected", type: nativePtrType),
                (name: "newValue", type: nativePtrType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndSet",
            returnType: nativePtrType,
            parameters: [(name: "newValue", type: nativePtrType)],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentToStringMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicClass(
        named name: String,
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        valueType: TypeID,
        constructorDefault: Bool,
        replacement: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> ClassType {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName), symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }

        let classType = ClassType(classSymbol: classSymbol, args: [], nullability: .nonNull)
        let ownerType = types.make(.classType(classType))
        symbols.setPropertyType(ownerType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Use \(replacement) instead.",
                    replaceWith: replacement
                ),
            ],
            to: classSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            parameters: [(name: "value", type: valueType)],
            defaultValues: [constructorDefault],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMutableProperty(
            ownerSymbol: classSymbol,
            name: "value",
            propertyType: valueType,
            symbols: symbols,
            interner: interner
        )
        return classType
    }

    private func registerNativeConcurrentAtomicNumericMembers(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        addAndGetParameterTypes: [TypeID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSet",
            returnType: types.booleanType,
            parameters: [(name: "expected", type: valueType), (name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSwap",
            returnType: valueType,
            parameters: [(name: "expected", type: valueType), (name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndSet",
            returnType: valueType,
            parameters: [(name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        for parameterType in addAndGetParameterTypes {
            registerNativeConcurrentAtomicCoreMember(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                name: "addAndGet",
                returnType: valueType,
                parameters: [(name: "delta", type: parameterType)],
                symbols: symbols,
                interner: interner
            )
        }
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndAdd",
            returnType: valueType,
            parameters: [(name: "delta", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        for name in ["getAndIncrement", "getAndDecrement", "incrementAndGet", "decrementAndGet"] {
            registerNativeConcurrentAtomicCoreMember(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                name: name,
                returnType: valueType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }
        for name in ["increment", "decrement"] {
            registerNativeConcurrentAtomicCoreMember(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                name: name,
                returnType: types.unitType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }
        registerNativeConcurrentToStringMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentAtomicCoreMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerNativeConcurrentMemberFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: name,
            returnType: returnType,
            parameters: parameters,
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
    }

    func registerNativeConcurrentToStringMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerNativeConcurrentMemberFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "toString",
            returnType: types.stringType,
            parameters: [],
            defaultValues: [],
            flags: [.synthetic, .overrideMember, .openType],
            symbols: symbols,
            interner: interner
        )
    }
}
