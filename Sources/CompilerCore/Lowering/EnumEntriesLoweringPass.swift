import Foundation

/// Rewrites `Color.entries` property accesses to `entries$get()` getter calls.
/// Runs after DataEnumSealedSynthesisPass which creates the `entries$get` helper.
final class EnumEntriesLoweringPass: LoweringPass {
    static let name = "EnumEntriesLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }
        let entriesName = ctx.interner.intern("entries")
        let entriesGetName = ctx.interner.intern("entries$get")

        module.arena.transformFunctions { function in
            var newBody: [KIRInstruction] = []
            for instruction in function.body {
                // Match call/virtualCall where callee is "entries" or symbol is
                // a property named "entries" owned by an enum class.
                if let rewritten = self.rewriteEntriesAccess(
                    instruction: instruction,
                    sema: sema,
                    interner: ctx.interner,
                    arena: module.arena,
                    entriesName: entriesName,
                    entriesGetName: entriesGetName
                ) {
                    newBody.append(rewritten)
                    continue
                }
                // Rewrite constValue(.symbolRef(entriesPropSym)) patterns
                // emitted by BuildKIR for property references.
                if let rewritten = self.rewriteEntriesConstValue(
                    instruction: instruction,
                    sema: sema,
                    interner: ctx.interner,
                    arena: module.arena,
                    entriesName: entriesName,
                    entriesGetName: entriesGetName
                ) {
                    newBody.append(rewritten)
                    continue
                }
                newBody.append(instruction)
            }
            var updated = function
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }

    /// Rewrites `.call(symbol: entriesPropSym, callee: "entries", ...)` or
    /// `.call(symbol: entriesPropSym, callee: "get", ...)` to a call to the
    /// synthesized `entries$get` function.
    private func rewriteEntriesAccess(
        instruction: KIRInstruction,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        entriesName: InternedString,
        entriesGetName: InternedString
    ) -> KIRInstruction? {
        guard case let .call(symbol, _, _, result, _, _, _) = instruction,
              let propSym = symbol,
              let propInfo = sema.symbols.symbol(propSym),
              propInfo.kind == .property,
              propInfo.name == entriesName
        else {
            return nil
        }
        // Verify the property belongs to an enum class (or its companion).
        guard let enumClassSymbol = findOwnerEnumClass(for: propSym, sema: sema) else {
            return nil
        }
        guard let classSym = sema.symbols.symbol(enumClassSymbol) else {
            return nil
        }
        // Look up the synthesized entries$get function.
        // It may be owned by the companion or by the enum class itself.
        let ownerFQName = classSym.fqName
        let getterFQName = ownerFQName + [entriesGetName]
        // Also try companion owner
        let companionOwner = sema.symbols.companionObjectSymbol(for: enumClassSymbol)
        let companionFQName: [InternedString]? = companionOwner.flatMap { companion in
            sema.symbols.symbol(companion)?.fqName
        }
        let getterSymbol: SymbolID? =
            sema.symbols.lookupAll(fqName: getterFQName).first(where: { id in
                sema.symbols.symbol(id).map { $0.kind == .function } ?? false
            }) ?? companionFQName.flatMap { fq in
                sema.symbols.lookupAll(fqName: fq + [entriesGetName]).first(where: { id in
                    sema.symbols.symbol(id).map { $0.kind == .function } ?? false
                })
            }
        guard let getter = getterSymbol else {
            return nil
        }
        let targetResult = result ?? arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: sema.types.anyType
        )
        return .call(
            symbol: getter,
            callee: entriesGetName,
            arguments: [],
            result: targetResult,
            canThrow: false,
            thrownResult: nil
        )
    }

    /// Rewrites `constValue(result, .symbolRef(entriesPropSym))` to an
    /// `entries$get()` call. BuildKIR may emit this pattern for property
    /// references in some code paths.
    private func rewriteEntriesConstValue(
        instruction: KIRInstruction,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        entriesName: InternedString,
        entriesGetName: InternedString
    ) -> KIRInstruction? {
        guard case let .constValue(cvResult, value) = instruction,
              case let .symbolRef(sym) = value,
              let symInfo = sema.symbols.symbol(sym),
              symInfo.kind == .property,
              symInfo.name == entriesName
        else {
            return nil
        }
        guard let enumClassSymbol = findOwnerEnumClass(for: sym, sema: sema) else {
            return nil
        }
        guard let classSym = sema.symbols.symbol(enumClassSymbol) else {
            return nil
        }
        let ownerFQName = classSym.fqName
        let getterFQName = ownerFQName + [entriesGetName]
        let companionOwner = sema.symbols.companionObjectSymbol(for: enumClassSymbol)
        let companionFQName: [InternedString]? = companionOwner.flatMap { companion in
            sema.symbols.symbol(companion)?.fqName
        }
        let getterSymbol: SymbolID? =
            sema.symbols.lookupAll(fqName: getterFQName).first(where: { id in
                sema.symbols.symbol(id).map { $0.kind == .function } ?? false
            }) ?? companionFQName.flatMap { fq in
                sema.symbols.lookupAll(fqName: fq + [entriesGetName]).first(where: { id in
                    sema.symbols.symbol(id).map { $0.kind == .function } ?? false
                })
            }
        guard let getter = getterSymbol else {
            return nil
        }
        return .call(
            symbol: getter,
            callee: entriesGetName,
            arguments: [],
            result: cvResult,
            canThrow: false,
            thrownResult: nil
        )
    }

    /// Walk up the parent chain to find the enum class that owns this property.
    /// The property may be directly on the enum class, or on its companion object.
    private func findOwnerEnumClass(for symbol: SymbolID, sema: SemaModule) -> SymbolID? {
        var current: SymbolID? = symbol
        while let candidate = current {
            guard let info = sema.symbols.symbol(candidate) else { return nil }
            if info.kind == .enumClass {
                return candidate
            }
            current = sema.symbols.parentSymbol(for: candidate)
        }
        return nil
    }
}
