import Foundation

// STDLIB-CORO-ABI-001: Synthetic stubs for AbstractCoroutineContextElement,
// AbstractCoroutineContextKey, and supplementary CoroutineContext ABI members.
//
// kotlin.coroutines.CoroutineContext (interface) with get/fold/minusKey/plus,
// nested Element (interface : CoroutineContext) + Key<E> (phantom-typed interface),
// and the two abstract base classes that user-defined context elements extend:
//
//   abstract class AbstractCoroutineContextElement(val key: Key<*>) : CoroutineContext.Element
//   abstract class AbstractCoroutineContextKey<B : Element, E : B>(
//       baseKey: Key<B>, safeCast: (Element) -> E?)
//       : Key<E>

extension DataFlowSemaPhase {
    func registerSyntheticCoroutinesABIStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // ── Package tree ────────────────────────────────────────────────────
        let kotlinCoroutinesPkg = ensurePackage(
            path: ["kotlin", "coroutines"],
            symbols: symbols,
            interner: interner
        )

        // ── Resolve already-registered CoroutineContext & nested types ──────
        let coroutineContextFQName = kotlinCoroutinesPkg + [interner.intern("CoroutineContext")]

        let coroutineContextSymbol: SymbolID = if let existing = symbols.lookup(fqName: coroutineContextFQName) {
            existing
        } else {
            ensureInterfaceSymbol(
                named: "CoroutineContext",
                in: kotlinCoroutinesPkg,
                symbols: symbols,
                interner: interner
            )
        }
        let coroutineContextType = types.make(.classType(ClassType(
            classSymbol: coroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Element (nested interface) ─────────────────────────────────────────
        let elementFQName = coroutineContextFQName + [interner.intern("Element")]
        let coroutineContextElementSymbol: SymbolID = if let existing = symbols.lookup(fqName: elementFQName) {
            existing
        } else {
            ensureInterfaceSymbol(
                named: "Element",
                in: coroutineContextFQName,
                symbols: symbols,
                interner: interner
            )
        }
        let coroutineContextElementType = types.make(.classType(ClassType(
            classSymbol: coroutineContextElementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setDirectSupertypes([coroutineContextSymbol], for: coroutineContextElementSymbol)
        types.setNominalDirectSupertypes([coroutineContextSymbol], for: coroutineContextElementSymbol)

        // Key<E : Element> (nested interface) ────────────────────────────────
        let keyFQName = coroutineContextFQName + [interner.intern("Key")]
        let coroutineContextKeySymbol: SymbolID = if let existing = symbols.lookup(fqName: keyFQName) {
            existing
        } else {
            ensureInterfaceSymbol(
                named: "Key",
                in: coroutineContextFQName,
                symbols: symbols,
                interner: interner
            )
        }

        // Resolve or create the Key type-parameter <E : Element>
        let keyTypeParamName = interner.intern("E")
        let keyTypeParamFQName = keyFQName + [interner.intern("$synthetic"), keyTypeParamName]
        let keyTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: keyTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: keyTypeParamName,
                fqName: keyTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(coroutineContextKeySymbol, for: keyTypeParamSymbol)
        let keyTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: keyTypeParamSymbol,
            nullability: .nonNull
        )))
        symbols.setTypeParameterUpperBounds([coroutineContextElementType], for: keyTypeParamSymbol)
        types.setNominalTypeParameterSymbols([keyTypeParamSymbol], for: coroutineContextKeySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: coroutineContextKeySymbol)
        let coroutineContextKeyType = types.make(.classType(ClassType(
            classSymbol: coroutineContextKeySymbol,
            args: [.invariant(keyTypeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineContextKeyType, for: coroutineContextKeySymbol)

        // ── AbstractCoroutineContextElement ───────────────────────────────────
        //
        //   abstract class AbstractCoroutineContextElement(val key: Key<*>) : Element
        //
        let aceFQName = kotlinCoroutinesPkg + [interner.intern("AbstractCoroutineContextElement")]
        let aceSymbol: SymbolID = if let existing = symbols.lookup(fqName: aceFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: interner.intern("AbstractCoroutineContextElement"),
                fqName: aceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }
        let aceType = types.make(.classType(ClassType(
            classSymbol: aceSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(aceType, for: aceSymbol)
        symbols.setDirectSupertypes([coroutineContextElementSymbol], for: aceSymbol)
        types.setNominalDirectSupertypes([coroutineContextElementSymbol], for: aceSymbol)

        // Primary constructor: AbstractCoroutineContextElement(key: Key<*>)
        let aceCtorFQName = aceFQName + [interner.intern("<init>")]
        if symbols.lookup(fqName: aceCtorFQName) == nil {
            let ctorSymbol = symbols.define(
                kind: .constructor,
                name: interner.intern("<init>"),
                fqName: aceCtorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(aceSymbol, for: ctorSymbol)
            let keyStarType = types.make(.classType(ClassType(
                classSymbol: coroutineContextKeySymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let keyParamName = interner.intern("key")
            let keyParamSymbol = symbols.define(
                kind: .valueParameter,
                name: keyParamName,
                fqName: aceCtorFQName + [keyParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: keyParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: aceType,
                    parameterTypes: [keyStarType],
                    returnType: aceType,
                    isSuspend: false,
                    valueParameterSymbols: [keyParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: []
                ),
                for: ctorSymbol
            )
        }

        // Synthetic `key` property on AbstractCoroutineContextElement
        let aceKeyPropFQName = aceFQName + [interner.intern("key")]
        if symbols.lookup(fqName: aceKeyPropFQName) == nil {
            let keyPropSymbol = symbols.define(
                kind: .property,
                name: interner.intern("key"),
                fqName: aceKeyPropFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(aceSymbol, for: keyPropSymbol)
            let keyStarType = types.make(.classType(ClassType(
                classSymbol: coroutineContextKeySymbol,
                args: [.star],
                nullability: .nonNull
            )))
            symbols.setPropertyType(keyStarType, for: keyPropSymbol)
        }

        // ── AbstractCoroutineContextKey<B : Element, E : B> ──────────────────
        //
        //   abstract class AbstractCoroutineContextKey<B : Element, E : B>(
        //       baseKey: Key<B>,
        //       safeCast: (Element) -> E?
        //   ) : Key<E>
        //
        let ackFQName = kotlinCoroutinesPkg + [interner.intern("AbstractCoroutineContextKey")]
        let ackSymbol: SymbolID = if let existing = symbols.lookup(fqName: ackFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: interner.intern("AbstractCoroutineContextKey"),
                fqName: ackFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        // Type parameters B : Element, E : B
        let ackBName = interner.intern("B")
        let ackBFQName = ackFQName + [interner.intern("$synthetic"), ackBName]
        let ackBSymbol: SymbolID = if let existing = symbols.lookup(fqName: ackBFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: ackBName,
                fqName: ackBFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ackSymbol, for: ackBSymbol)
        symbols.setTypeParameterUpperBounds([coroutineContextElementType], for: ackBSymbol)
        let ackBType = types.make(.typeParam(TypeParamType(symbol: ackBSymbol, nullability: .nonNull)))

        let ackEName = interner.intern("E")
        let ackEFQName = ackFQName + [interner.intern("$synthetic"), ackEName]
        let ackESymbol: SymbolID = if let existing = symbols.lookup(fqName: ackEFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: ackEName,
                fqName: ackEFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ackSymbol, for: ackESymbol)
        symbols.setTypeParameterUpperBounds([ackBType], for: ackESymbol)
        let ackEType = types.make(.typeParam(TypeParamType(symbol: ackESymbol, nullability: .nonNull)))

        types.setNominalTypeParameterSymbols([ackBSymbol, ackESymbol], for: ackSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: ackSymbol)

        let ackKeyType = types.make(.classType(ClassType(
            classSymbol: coroutineContextKeySymbol,
            args: [.invariant(ackEType)],
            nullability: .nonNull
        )))
        let ackType = types.make(.classType(ClassType(
            classSymbol: ackSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ackType, for: ackSymbol)
        // AbstractCoroutineContextKey<B,E> : Key<E>
        symbols.setDirectSupertypes([coroutineContextKeySymbol], for: ackSymbol)
        types.setNominalDirectSupertypes([coroutineContextKeySymbol], for: ackSymbol)

        // Primary constructor: AbstractCoroutineContextKey(baseKey: Key<B>, safeCast: (Element) -> E?)
        let ackCtorFQName = ackFQName + [interner.intern("<init>")]
        if symbols.lookup(fqName: ackCtorFQName) == nil {
            let ctorSymbol = symbols.define(
                kind: .constructor,
                name: interner.intern("<init>"),
                fqName: ackCtorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ackSymbol, for: ctorSymbol)
            let baseKeyType = types.make(.classType(ClassType(
                classSymbol: coroutineContextKeySymbol,
                args: [.invariant(ackBType)],
                nullability: .nonNull
            )))
            let safeCastType = types.make(.functionType(FunctionType(
                params: [coroutineContextElementType],
                returnType: types.makeNullable(ackEType),
                isSuspend: false,
                nullability: .nonNull
            )))
            let baseKeyParamName = interner.intern("baseKey")
            let baseKeyParamSymbol = symbols.define(
                kind: .valueParameter,
                name: baseKeyParamName,
                fqName: ackCtorFQName + [baseKeyParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let safeCastParamName = interner.intern("safeCast")
            let safeCastParamSymbol = symbols.define(
                kind: .valueParameter,
                name: safeCastParamName,
                fqName: ackCtorFQName + [safeCastParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: baseKeyParamSymbol)
            symbols.setParentSymbol(ctorSymbol, for: safeCastParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ackType,
                    parameterTypes: [baseKeyType, safeCastType],
                    returnType: ackType,
                    isSuspend: false,
                    valueParameterSymbols: [baseKeyParamSymbol, safeCastParamSymbol],
                    valueParameterHasDefaultValues: [false, false],
                    valueParameterIsVararg: [false, false],
                    typeParameterSymbols: [ackBSymbol, ackESymbol]
                ),
                for: ctorSymbol
            )
        }

        // ── CoroutineContext.plus operator ────────────────────────────────────
        //   operator fun CoroutineContext.plus(context: CoroutineContext): CoroutineContext
        let plusFQName = coroutineContextFQName + [interner.intern("plus")]
        if symbols.lookup(fqName: plusFQName) == nil {
            let plusSymbol = symbols.define(
                kind: .function,
                name: interner.intern("plus"),
                fqName: plusFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(coroutineContextSymbol, for: plusSymbol)
            let contextParamName = interner.intern("context")
            let contextParamSymbol = symbols.define(
                kind: .valueParameter,
                name: contextParamName,
                fqName: plusFQName + [contextParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(plusSymbol, for: contextParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: coroutineContextType,
                    parameterTypes: [coroutineContextType],
                    returnType: coroutineContextType,
                    isSuspend: false,
                    valueParameterSymbols: [contextParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: []
                ),
                for: plusSymbol
            )
            symbols.setExternalLinkName("kk_context_plus", for: plusSymbol)
        }
    }
}
