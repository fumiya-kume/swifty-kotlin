import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: FreezableAtomicReference<T> class.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - FreezableAtomicReference<T>

    func registerNativeConcurrentFreezableAtomicReference(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("FreezableAtomicReference")
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

        let typeParamName = interner.intern("T")
        let typeParamFQName = classFQName + [typeParamName]
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
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classSymbol, for: typeParamSymbol)
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        symbols.setPropertyType(classType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Use kotlin.concurrent.atomics.AtomicReference instead.",
                    replaceWith: "kotlin.concurrent.atomics.AtomicReference"
                ),
            ],
            to: classSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            externalLinkName: "kk_freezable_atomic_ref_create",
            parameters: [(name: "value", type: typeParamType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMutableProperty(
            ownerSymbol: classSymbol,
            name: "value",
            propertyType: typeParamType,
            getterLinkName: "kk_freezable_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "compareAndSet",
            externalLinkName: "kk_freezable_atomic_ref_compareAndSet",
            returnType: types.booleanType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "newValue", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "compareAndSwap",
            externalLinkName: "kk_freezable_atomic_ref_compareAndSwap",
            returnType: typeParamType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "newValue", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentToStringMember(
            ownerSymbol: classSymbol,
            ownerType: classType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}
