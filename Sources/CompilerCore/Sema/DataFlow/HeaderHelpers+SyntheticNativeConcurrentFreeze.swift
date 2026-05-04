import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: `<T>.freeze()` and
/// `Any?.isFrozen` legacy-memory-manager surfaces.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - freeze / isFrozen

    func registerNativeConcurrentFreezeAndIsFrozen(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let freezeName = interner.intern("freeze")
        let freezeFQName = packageFQName + [freezeName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = freezeFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParameterSymbol)
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))

        registerNativeConcurrentPackageFunction(
            named: "freeze",
            packageFQName: packageFQName,
            receiverType: typeParameterType,
            returnType: typeParameterType,
            parameters: [],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Support for the legacy memory manager has been completely removed. Usages of this function can be safely dropped.",
                    replaceWith: "this"
                ),
            ],
            externalLinkName: "kk_freeze_object",
            symbols: symbols,
            interner: interner
        )

        registerNativeConcurrentPackageExtensionProperty(
            named: "isFrozen",
            packageFQName: packageFQName,
            receiverType: types.nullableAnyType,
            returnType: types.booleanType,
            annotations: [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Support for the legacy memory manager has been completely removed. Consequently, this property is always `false`.",
                    replaceWith: "false"
                ),
            ],
            externalLinkName: "kk_is_frozen",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerNativeConcurrentPackageExtensionProperty(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        annotations: [MetadataAnnotationRecord] = [],
        externalLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: id) == receiverType
        }) {
            symbols.setPropertyType(returnType, for: existing)
            appendNativeConcurrentMetadataAnnotations(annotations, to: existing, symbols: symbols)
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType
                    ),
                    for: getterSymbol
                )
                appendNativeConcurrentMetadataAnnotations(annotations, to: getterSymbol, symbols: symbols)
                if let externalLinkName {
                    symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
                }
            }
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        appendNativeConcurrentMetadataAnnotations(annotations, to: propertySymbol, symbols: symbols)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        }

        let getterAccessorName = interner.intern("$get")
        let getterSymbol = symbols.define(
            kind: .function,
            name: getterAccessorName,
            fqName: propertyFQName + [getterAccessorName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: getterSymbol
        )
        appendNativeConcurrentMetadataAnnotations(annotations, to: getterSymbol, symbols: symbols)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
        }
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
    }
}
