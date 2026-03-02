import Foundation

// CLASS-005: Validate open/final/override modifier constraints.
// In Kotlin, classes are final by default. Subclassing a non-open
// (non-abstract, non-sealed, non-interface) class is an error.
// Overriding a final member is an error. Hiding a parent member
// without the `override` modifier is an error.

/// Lightweight context to avoid passing many parameters.
struct OpenFinalOverrideContext {
    let ast: ASTModule
    let symbols: SymbolTable
    let bindings: BindingTable
    let diagnostics: DiagnosticEngine
    let interner: StringInterner
}

extension DataFlowSemaPhase {
    func validateOpenFinalOverride(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let ctx = OpenFinalOverrideContext(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            diagnostics: diagnostics,
            interner: interner
        )
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateOFODecl(declID, ctx: ctx)
            }
        }
    }

    // MARK: - Per-declaration dispatch

    private func validateOFODecl(
        _ declID: DeclID,
        ctx: OpenFinalOverrideContext
    ) {
        guard let symbol = ctx.bindings.declSymbols[declID],
              let decl = ctx.ast.arena.decl(declID),
              ctx.symbols.symbol(symbol) != nil
        else {
            return
        }

        let info = extractDeclInfo(decl)
        guard let info else { return }

        for nestedID in info.nestedClasses {
            validateOFODecl(nestedID, ctx: ctx)
        }

        if let range = info.declRange {
            validateSupertypesAreOpen(
                symbol: symbol,
                declRange: range,
                ctx: ctx
            )
        }

        validateMemberOverrides(
            info.memberFunctions,
            symbol: symbol,
            ctx: ctx
        )
        validateMemberOverrides(
            info.memberProperties,
            symbol: symbol,
            ctx: ctx
        )
    }

    // MARK: - Declaration info extraction

    private struct OFODeclInfo {
        let memberFunctions: [DeclID]
        let memberProperties: [DeclID]
        let nestedClasses: [DeclID]
        let declRange: SourceRange?
    }

    private func extractDeclInfo(
        _ decl: Decl
    ) -> OFODeclInfo? {
        switch decl {
        case let .classDecl(d):
            OFODeclInfo(
                memberFunctions: d.memberFunctions,
                memberProperties: d.memberProperties,
                nestedClasses: d.nestedClasses,
                declRange: d.range
            )
        case let .objectDecl(d):
            OFODeclInfo(
                memberFunctions: d.memberFunctions,
                memberProperties: d.memberProperties,
                nestedClasses: d.nestedClasses,
                declRange: d.range
            )
        case let .interfaceDecl(d):
            OFODeclInfo(
                memberFunctions: [],
                memberProperties: [],
                nestedClasses: d.nestedClasses,
                declRange: nil
            )
        default:
            nil
        }
    }

    // MARK: - Check 1: supertype openness

    private func validateSupertypesAreOpen(
        symbol: SymbolID,
        declRange: SourceRange,
        ctx: OpenFinalOverrideContext
    ) {
        for supertypeID in ctx.symbols.directSupertypes(for: symbol) {
            guard let sup = ctx.symbols.symbol(supertypeID) else {
                continue
            }
            if isSubclassable(sup) { continue }
            let name = sup.fqName
                .map { ctx.interner.resolve($0) }
                .joined(separator: ".")
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-FINAL",
                "Cannot inherit from final class '\(name)'. "
                    + "Mark it as 'open' to allow subclassing.",
                range: declRange
            )
        }
    }

    private func isSubclassable(_ sym: SemanticSymbol) -> Bool {
        if sym.kind == .interface { return true }
        if sym.flags.contains(.abstractType) { return true }
        if sym.flags.contains(.sealedType) { return true }
        if sym.flags.contains(.openType) { return true }
        return false
    }

    // MARK: - Check 2 & 3: member override constraints

    private func validateMemberOverrides(
        _ memberDeclIDs: [DeclID],
        symbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        for memberDeclID in memberDeclIDs {
            guard let memberDecl = ctx.ast.arena.decl(memberDeclID),
                  ctx.bindings.declSymbols[memberDeclID] != nil
            else { continue }

            let memberMeta = extractMemberMeta(memberDecl)
            guard let memberMeta else { continue }

            if memberMeta.hasOverride {
                validateOverrideTarget(
                    memberName: memberMeta.name,
                    memberRange: memberMeta.range,
                    ownerSymbol: symbol,
                    ctx: ctx
                )
            } else {
                validateMissingOverride(
                    memberName: memberMeta.name,
                    memberRange: memberMeta.range,
                    ownerSymbol: symbol,
                    ctx: ctx
                )
            }
        }
    }

    private struct MemberMeta {
        let name: InternedString
        let range: SourceRange
        let hasOverride: Bool
    }

    private func extractMemberMeta(
        _ decl: Decl
    ) -> MemberMeta? {
        switch decl {
        case let .funDecl(d):
            MemberMeta(
                name: d.name,
                range: d.range,
                hasOverride: d.modifiers.contains(.override)
            )
        case let .propertyDecl(d):
            MemberMeta(
                name: d.name,
                range: d.range,
                hasOverride: d.modifiers.contains(.override)
            )
        default:
            nil
        }
    }

    // MARK: - Check 2: override target is not final

    private func validateOverrideTarget(
        memberName: InternedString,
        memberRange: SourceRange,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        let parent = findInheritedMember(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols
        )
        guard let parent else { return }
        guard let parentSym = ctx.symbols.symbol(parent.memberID) else {
            return
        }

        if isMemberOverridable(parentSym, parent: parent) { return }

        let name = ctx.interner.resolve(memberName)
        let ownerName = ctx.interner.resolve(parent.ownerName)
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-FINAL",
            "'\(name)' in '\(ownerName)' is final and cannot be overridden.",
            range: memberRange
        )
    }

    // MARK: - Check 3: missing override modifier

    private func validateMissingOverride(
        memberName: InternedString,
        memberRange: SourceRange,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        let parent = findInheritedMember(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols
        )
        guard let parent else { return }
        guard let parentSym = ctx.symbols.symbol(parent.memberID) else {
            return
        }

        guard isMemberOverridable(parentSym, parent: parent) else {
            return
        }

        let name = ctx.interner.resolve(memberName)
        let ownerName = ctx.interner.resolve(parent.ownerName)
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-OVERRIDE",
            "'\(name)' hides member of supertype '\(ownerName)' "
                + "and needs 'override' modifier.",
            range: memberRange
        )
    }

    // MARK: - Overridability check

    /// A member is overridable when it belongs to an interface,
    /// is explicitly `open`, is `abstract`, or is a non-final
    /// `override` (override members are implicitly open in Kotlin
    /// unless also marked `final`).
    private func isMemberOverridable(
        _ sym: SemanticSymbol,
        parent: OFOInheritedMember
    ) -> Bool {
        if parent.ownerIsInterface { return true }
        if sym.flags.contains(.openType) { return true }
        if sym.flags.contains(.abstractType) { return true }
        // An override member is implicitly open unless marked final.
        if sym.flags.contains(.overrideMember),
           !sym.flags.contains(.finalMember)
        {
            return true
        }
        return false
    }

    // MARK: - Inherited member lookup (BFS)

    private struct OFOInheritedMember {
        let memberID: SymbolID
        let ownerName: InternedString
        let ownerIsInterface: Bool
    }

    private func findInheritedMember(
        named memberName: InternedString,
        for classSymbol: SymbolID,
        symbols: SymbolTable
    ) -> OFOInheritedMember? {
        var visited: Set<SymbolID> = [classSymbol]
        var queue = symbols.directSupertypes(for: classSymbol)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            guard let sym = symbols.symbol(current) else { continue }

            for childID in symbols.children(ofFQName: sym.fqName) {
                guard let child = symbols.symbol(childID) else {
                    continue
                }
                let isMatch = child.kind == .function
                    || child.kind == .property
                if isMatch, child.name == memberName {
                    return OFOInheritedMember(
                        memberID: childID,
                        ownerName: sym.name,
                        ownerIsInterface: sym.kind == .interface
                    )
                }
            }

            queue.append(
                contentsOf: symbols.directSupertypes(for: current)
            )
        }
        return nil
    }
}
