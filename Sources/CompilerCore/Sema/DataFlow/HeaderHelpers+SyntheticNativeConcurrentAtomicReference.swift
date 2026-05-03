import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Legacy AtomicReference<T> class under kotlin.native.concurrent.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - AtomicReference<T> (legacy kotlin.native.concurrent)

    func registerNativeConcurrentAtomicReference(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let atomicRefName = interner.intern("AtomicReference")
        let atomicRefFQName = packageFQName + [atomicRefName]

        let atomicRefSymbol: SymbolID
        if let existing = symbols.lookup(fqName: atomicRefFQName), symbols.symbol(existing)?.kind == .class {
            atomicRefSymbol = existing
        } else {
            atomicRefSymbol = symbols.define(
                kind: .class,
                name: atomicRefName,
                fqName: atomicRefFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: atomicRefSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = atomicRefFQName + [typeParamName]
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
        let atomicRefType = types.make(.classType(ClassType(
            classSymbol: atomicRefSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: atomicRefSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: atomicRefSymbol)
        symbols.setPropertyType(atomicRefType, for: atomicRefSymbol)

        // constructor(value: T): AtomicReference<T>
        let initName = interner.intern("<init>")
        let initFQName = atomicRefFQName + [initName]
        if symbols.lookupAll(fqName: initFQName).isEmpty {
            let initSymbol = symbols.define(
                kind: .function,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(atomicRefSymbol, for: initSymbol)
            symbols.setExternalLinkName("kk_native_atomic_ref_create", for: initSymbol)
            let paramName = interner.intern("value")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: initFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: paramSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [typeParamType],
                    returnType: atomicRefType,
                    isSuspend: false,
                    valueParameterSymbols: [paramSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        // value property: var T
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: atomicRefSymbol,
            name: "value",
            propertyType: typeParamType,
            getterLinkName: "kk_native_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )

        // compareAndSwap(expected: T, new: T): T
        registerNativeConcurrentMemberFunction(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            name: "compareAndSwap",
            externalLinkName: "kk_native_atomic_ref_compareAndSwap",
            returnType: typeParamType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "new", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // compareAndSet(expected: T, new: T): Boolean
        let boolType = types.make(.primitive(.boolean, .nonNull))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            name: "compareAndSet",
            externalLinkName: "kk_native_atomic_ref_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "new", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
    }
}
