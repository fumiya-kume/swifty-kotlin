/// Stdlib factory / java.io.File predicates and the primitive box-callee
/// table consulted by `rewriteCalls`.
///
/// Split out from `CollectionLiteralLoweringPass+CallRewrite.swift` to
/// keep the giant `rewriteCalls` body file scoped only to the rewrite
/// dispatcher.
extension CollectionLiteralConstructionLoweringPass {
    /// Recognizes both the legacy bare `HashSet` constructor name and the
    /// source-backed class constructor symbol emitted for the nominal class.
    func isHashSetConstructor(
        callee: InternedString,
        symbol: SymbolID?,
        result: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        if callee == lookup.hashSetName {
            return true
        }
        guard let sema = ctx.sema else { return false }
        let expectedFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("collections"),
            lookup.hashSetName,
        ]
        if let symbol,
           sema.symbols.symbol(symbol)?.kind == .constructor,
           let owner = sema.symbols.parentSymbol(for: symbol),
           let ownerInfo = sema.symbols.symbol(owner),
           ownerInfo.fqName == expectedFQName
        {
            return true
        }

        // Source-backed implicit constructors can lose their constructor
        // symbol while the call is converted to KIR. Recover the owner from
        // the resolved result type before falling back to the generic `<init>`
        // callee.
        guard callee == ctx.interner.intern("<init>"),
              let result,
              let resultType = module.arena.exprType(result),
              let resultClass = resolveClassType(resultType, sema: sema),
              let resultInfo = sema.symbols.symbol(resultClass.classSymbol)
        else {
            return false
        }
        return resultInfo.fqName == expectedFQName
    }

    /// Looks up the primitive boxing callee for `type`, resolving a value
    /// class to its underlying primitive first (see `resolveValueClassKind`)
    /// so `Meters` boxes exactly like the `Int` it wraps — matching
    /// `ABILoweringPass`'s typeParam boxing boundary
    /// (`typeParamBoxingBoundaryCallees`), which every other reference-type
    /// boxing boundary in this pass is documented to mirror. A value class
    /// implementing an interface stays boxed instead (see
    /// `effectiveValueClassUnderlyingType`), so it never reaches this path.
    func primitiveBoxCalleeName(
        for type: TypeID,
        types: TypeSystem,
        symbols: SymbolTable? = nil,
        interner: StringInterner
    ) -> InternedString? {
        let kind = resolveValueClassKind(types.kind(of: type), types: types, symbols: symbols)
        return BoxingCalleeTable(interner: interner).boxCallee(for: kind, requireNonNull: false)
    }

    /// Returns true when the resolved symbol's FQN matches one of the known
    /// `kotlin.collections.*` factory FQNs.  When the symbol is nil (unresolved)
    /// we conservatively allow the rewrite – the name check already passed and
    /// unresolved symbols are common for synthetic stubs that have no KIR-level
    /// symbol entry.
    func isStdlibCollectionFactory(
        symbol: SymbolID?,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        guard let sym = symbol,
              let resolved = ctx.sema?.symbols.symbol(sym)
        else {
            // No symbol info available – fall through to name-only rewrite
            // (backwards compatible with pre-symbol resolution passes).
            return true
        }
        let fqName = resolved.fqName
        // Match against known stdlib collection factory FQNs
        return fqName == lookup.emptyListFQName
            || fqName == lookup.emptyArrayFQName
            || fqName == lookup.listOfFQName
            || fqName == lookup.mutableListOfFQName
            || fqName == lookup.arrayListOfFQName
            || fqName == lookup.listOfNotNullFQName
            || fqName == lookup.emptySetFQName
            || fqName == lookup.setOfFQName
            || fqName == lookup.setOfNotNullFQName
            || fqName == lookup.mutableSetOfFQName
            || fqName == lookup.linkedSetOfFQName
            || fqName == lookup.hashSetOfFQName
            || fqName == lookup.emptyMapFQName
            || fqName == lookup.mapOfFQName
            || fqName == lookup.mutableMapOfFQName
            || fqName == lookup.hashMapOfFQName
            || fqName == lookup.linkedMapOfFQName
    }

    /// Source-backed concrete classes lower through the same runtime bridge as
    /// the historical name-based constructor path. The resolved callee is
    /// `<init>` once ArrayList is a real class, so the owner FQName is the
    /// authoritative discriminator.
    func isStdlibArrayListConstructor(
        symbol: SymbolID?,
        callee: InternedString,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        if lookup.mutableListConstructorNames.contains(callee) {
            return true
        }
        guard let symbol,
              let resolved = ctx.sema?.symbols.symbol(symbol),
              resolved.kind == .constructor
        else {
            return false
        }
        return resolved.fqName == [
            lookup.kotlinName,
            ctx.interner.intern("collections"),
            lookup.arrayListName,
            lookup.initName,
        ]
    }

    func isStdlibArrayFactoryCall(
        symbol: SymbolID?,
        callee: InternedString,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        if lookup.arrayOfFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx)
        {
            return true
        }
        return isSourceBackedPrimitiveArrayFactory(
            symbol,
            sema: ctx.sema,
            interner: ctx.interner
        )
    }

    func isCollectionCopyConstructorArgument(
        _ argument: KIRExprID,
        module: KIRModule,
        ctx: KIRContext
    ) -> Bool {
        guard let sema = ctx.sema,
              let argumentType = module.arena.exprType(argument)
        else {
            return false
        }

        let nonNullType = sema.types.makeNonNullable(argumentType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }

        let kotlinCollectionsFQName = [ctx.interner.intern("kotlin"), ctx.interner.intern("collections")]
        guard symbol.fqName.count >= 3,
              Array(symbol.fqName.dropLast()) == kotlinCollectionsFQName
        else {
            return false
        }

        let simpleName = symbol.fqName.last ?? symbol.name
        switch ctx.interner.resolve(simpleName) {
        case "List", "MutableList", "ArrayList",
             "AbstractList", "AbstractMutableList",
             "Set", "MutableSet", "HashSet", "LinkedHashSet",
             "AbstractSet", "AbstractMutableSet",
             "Collection", "MutableCollection",
             "AbstractCollection", "AbstractMutableCollection":
            return true
        default:
            return false
        }
    }

    func isJavaIOFileMember(
        symbol: SymbolID?,
        ctx: KIRContext,
        interner: StringInterner
    ) -> Bool {
        guard let symbol,
              let resolved = ctx.sema?.symbols.symbol(symbol)
        else {
            return false
        }

        let javaIOFilePrefix: [InternedString] = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]
        return resolved.fqName.starts(with: javaIOFilePrefix)
    }

    /// True when the resolved callee is a bundled Kotlin source declaration
    /// or an imported library symbol, meaning the lowering pass should not
    /// rewrite it to a `kk_*` runtime helper.
    func isSourceBacked(
        symbol: SymbolID?,
        ctx: KIRContext
    ) -> Bool {
        guard let symbol,
              let sema = ctx.sema,
              sema.symbols.symbol(symbol) != nil
        else {
            return false
        }
        return sema.symbols.isSourceBackedSymbol(symbol)
    }

    /// True when the resolved callee's receiver type is `kotlin.sequences.Sequence<T>`.
    /// Used to keep source Sequence `map`/`filter` routed through the runtime
    /// pipeline while allowing List/Map/Set source `map`/`filter` to lower normally.
    func isSequenceReceiverType(
        symbol: SymbolID,
        ctx: KIRContext
    ) -> Bool {
        guard let sema = ctx.sema,
              let signature = sema.symbols.functionSignature(for: symbol),
              let receiverType = signature.receiverType,
              let (_, classSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
        else {
            return false
        }
        let expected = [ctx.interner.intern("kotlin"), ctx.interner.intern("sequences"), ctx.interner.intern("Sequence")]
        return classSymbol.fqName == expected
    }
}
