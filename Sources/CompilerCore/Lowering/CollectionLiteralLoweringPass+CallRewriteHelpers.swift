/// Stdlib factory / java.io.File predicates and the primitive box-callee
/// table consulted by `rewriteCalls`.
///
/// Split out from `CollectionLiteralLoweringPass+CallRewrite.swift` to
/// keep the giant `rewriteCalls` body file scoped only to the rewrite
/// dispatcher.
extension CollectionLiteralLoweringPass {
    func primitiveBoxCalleeName(
        for type: TypeID,
        types: TypeSystem,
        interner: StringInterner
    ) -> InternedString? {
        switch types.kind(of: type) {
        case .primitive(.int, _), .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return interner.intern("kk_box_int")
        case .primitive(.boolean, _):
            return interner.intern("kk_box_bool")
        case .primitive(.long, _), .primitive(.ulong, _):
            return interner.intern("kk_box_long")
        case .primitive(.float, _):
            return interner.intern("kk_box_float")
        case .primitive(.double, _):
            return interner.intern("kk_box_double")
        case .primitive(.char, _):
            return interner.intern("kk_box_char")
        default:
            return nil
        }
    }

    /// Returns true when the resolved symbol's FQN matches one of the known
    /// `kotlin.collections.*` factory FQNs.  When the symbol is nil (unresolved)
    /// we conservatively allow the rewrite – the name check already passed and
    /// unresolved symbols are common for synthetic stubs that have no KIR-level
    /// symbol entry.
    func isStdlibCollectionFactory(
        symbol: SymbolID?,
        callee: InternedString,
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

    func isStdlibArrayFactoryCall(
        symbol: SymbolID?,
        callee: InternedString,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        guard lookup.arrayOfFactoryNames.contains(callee) else {
            return false
        }
        return isStdlibCollectionFactory(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx)
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
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
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
}
