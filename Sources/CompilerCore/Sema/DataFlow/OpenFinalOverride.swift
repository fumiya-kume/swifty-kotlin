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
    let types: TypeSystem
    let diagnostics: DiagnosticEngine
    let interner: StringInterner
}

extension DataFlowSemaPhase {
    func validateOpenFinalOverride(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let ctx = OpenFinalOverrideContext(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            types: types,
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
        case let .classDecl(cls):
            OFODeclInfo(
                memberFunctions: cls.memberFunctions,
                memberProperties: cls.memberProperties,
                nestedClasses: cls.nestedClasses,
                declRange: cls.range
            )
        case let .objectDecl(obj):
            OFODeclInfo(
                memberFunctions: obj.memberFunctions,
                memberProperties: obj.memberProperties,
                nestedClasses: obj.nestedClasses,
                declRange: obj.range
            )
        case let .interfaceDecl(iface):
            OFODeclInfo(
                memberFunctions: iface.memberFunctions,
                memberProperties: iface.memberProperties,
                nestedClasses: iface.nestedClasses,
                declRange: iface.range
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
            
            // STDLIB-DATA-014: Check if attempting to inherit from a data class
            if sup.flags.contains(.dataType) {
                let name = sup.fqName
                    .map { ctx.interner.resolve($0) }
                    .joined(separator: ".")
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-DATA-INHERIT",
                    "Cannot inherit from data class '\(name)'. Data classes cannot be inherited from.",
                    range: declRange
                )
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

            let memberMeta = extractMemberMeta(memberDecl, declID: memberDeclID, ctx: ctx)
            guard let memberMeta else { continue }

            validateModifierCombinations(
                memberMeta: memberMeta,
                ownerSymbol: symbol,
                ctx: ctx
            )

            if memberMeta.hasOverride {
                validateOverrideTarget(
                    memberName: memberMeta.name,
                    memberRange: memberMeta.range,
                    ownerSymbol: symbol,
                    returnType: memberMeta.returnType,
                    visibility: memberMeta.visibility,
                    ctx: ctx
                )
                validateAbstractOverrideConstraints(
                    memberMeta: memberMeta,
                    ownerSymbol: symbol,
                    ctx: ctx
                )
                validateOverrideOpenness(
                    memberMeta: memberMeta,
                    ownerSymbol: symbol,
                    ctx: ctx
                )
                validateVisibilityConstraints(
                    memberMeta: memberMeta,
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
        let hasOpen: Bool
        let returnType: TypeID?
        let hasAbstract: Bool
        let hasFinal: Bool
        let visibility: Visibility
    }

    private func extractMemberMeta(
        _ decl: Decl,
        declID: DeclID,
        ctx: OpenFinalOverrideContext
    ) -> MemberMeta? {
        switch decl {
        case let .funDecl(fun):
            let returnType = ctx.bindings.declSymbols[declID]
                .flatMap { ctx.symbols.functionSignature(for: $0)?.returnType }
            return MemberMeta(
                name: fun.name,
                range: fun.range,
                hasOverride: fun.modifiers.contains(.override),
                hasOpen: fun.modifiers.contains(.open),
                returnType: returnType,
                hasAbstract: fun.modifiers.contains(.abstract),
                hasFinal: fun.modifiers.contains(.final),
                visibility: extractVisibility(from: fun.modifiers)
            )
        case let .propertyDecl(prop):
            return MemberMeta(
                name: prop.name,
                range: prop.range,
                hasOverride: prop.modifiers.contains(.override),
                hasOpen: prop.modifiers.contains(.open),
                returnType: nil,
                hasAbstract: prop.modifiers.contains(.abstract),
                hasFinal: prop.modifiers.contains(.final),
                visibility: extractVisibility(from: prop.modifiers)
            )
        default:
            return nil
        }
    }
    
    private func extractVisibility(from modifiers: Modifiers) -> Visibility {
        if modifiers.contains(.private) { return .private }
        if modifiers.contains(.protected) { return .protected }
        if modifiers.contains(.internal) { return .internal }
        if modifiers.contains(.public) { return .public }
        return .public // Default visibility
    }

    // MARK: - Check 7: visibility constraints validation

    private func validateVisibilityConstraints(
        memberMeta: MemberMeta,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        // STDLIB-INHERIT-018: Validate visibility constraints in inheritance hierarchy
        
        guard memberMeta.hasOverride else { return } // Only check overrides
        
        let memberName = ctx.interner.resolve(memberMeta.name)
        
        // Find the parent member being overridden
        let parent = findInheritedMember(
            named: memberMeta.name,
            for: ownerSymbol,
            symbols: ctx.symbols
        )
        guard let parent else { return }
        guard let parentSym = ctx.symbols.symbol(parent.memberID) else { return }
        
        // Rule 1: Cannot override with less visibility
        if !isVisibilityAllowed(childVisibility: memberMeta.visibility, parentVisibility: parentSym.visibility) {
            let parentVisibility = visibilityToString(parentSym.visibility)
            let childVisibility = visibilityToString(memberMeta.visibility)
            let parentName = ctx.interner.resolve(parent.ownerName)
            
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-VISIBILITY",
                "'\(memberName)' cannot override '\(parentName).\(memberName)' because it has \(childVisibility) visibility, but parent has \(parentVisibility) visibility.",
                range: memberMeta.range
            )
        }
        
        // Rule 2: private members cannot be overridden (shouldn't reach here due to lookup)
        if parentSym.visibility == .private {
            let parentName = ctx.interner.resolve(parent.ownerName)
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-VISIBILITY",
                "'\(memberName)' cannot override private member '\(parentName).\(memberName)'. Private members are not accessible for overriding.",
                range: memberMeta.range
            )
        }
    }
    
    private func isVisibilityAllowed(childVisibility: Visibility, parentVisibility: Visibility) -> Bool {
        // In Kotlin, child visibility must be the same or more permissive than parent
        switch parentVisibility {
        case .private:
            return childVisibility == .private
        case .protected:
            return childVisibility == .protected || childVisibility == .public || childVisibility == .internal
        case .internal:
            return childVisibility == .internal || childVisibility == .public
        case .public:
            return childVisibility == .public
        }
    }
    
    private func visibilityToString(_ visibility: Visibility) -> String {
        switch visibility {
        case .private: return "private"
        case .protected: return "protected"
        case .internal: return "internal"
        case .public: return "public"
        }
    }
    
    private func isSubclass(of parentFQName: [InternedString], child: [InternedString], symbols: SymbolTable) -> Bool {
        // Simplified check - in practice would need full inheritance hierarchy traversal
        guard parentFQName.count > 0, child.count > 0 else { return false }
        
        let parentName = parentFQName.last!
        let childName = child.last!
        
        // For now, just check if they're in the same package and child name suggests inheritance
        // A proper implementation would traverse the inheritance hierarchy
        return parentName != childName // Placeholder logic
    }

    // MARK: - Check 6: modifier combination validation

    private func validateModifierCombinations(
        memberMeta: MemberMeta,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        // STDLIB-INHERIT-018: Validate that modifier combinations follow Kotlin rules
        
        let memberName = ctx.interner.resolve(memberMeta.name)
        
        // Rule 1: abstract and final are mutually exclusive
        if memberMeta.hasAbstract && memberMeta.hasFinal {
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                "'\(memberName)' cannot be both 'abstract' and 'final'. These modifiers are mutually exclusive.",
                range: memberMeta.range
            )
        }
        
        // Rule 2: open and final are mutually exclusive
        if memberMeta.hasOverride && memberMeta.hasFinal {
            // This is actually valid (final override), so no error here
            // final override is allowed and means "override but don't allow further overriding"
        }
        
        // Rule 3: Check for invalid modifier combinations based on context
        guard let ownerSym = ctx.symbols.symbol(ownerSymbol) else { return }
        
        // Rule 3a: abstract members cannot be in final classes
        if memberMeta.hasAbstract && ownerSym.flags.contains(.finalMember) {
            let ownerName = ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                "'\(memberName)' cannot be abstract in final class '\(ownerName)'. Final classes cannot contain abstract members.",
                range: memberMeta.range
            )
        }
        
        // Rule 3b: override without actual parent implementation (already checked in validateOverrideTarget)
        // This is handled elsewhere
        
        // Rule 3c: Check interface-specific constraints
        if ownerSym.kind == .interface {
            // Interface members cannot be final
            if memberMeta.hasFinal {
                let ownerName = ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                    "'\(memberName)' cannot be final in interface '\(ownerName)'. Interface members cannot be final.",
                    range: memberMeta.range
                )
            }
            
            // Interface members are implicitly abstract, but explicit abstract is redundant
            if memberMeta.hasAbstract {
                let ownerName = ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
                ctx.diagnostics.warning(
                    "KSWIFTK-SEMA-REDUNDANT-MODIFIER",
                    "'\(memberName)' in interface '\(ownerName)' is implicitly abstract. 'abstract' modifier is redundant.",
                    range: memberMeta.range
                )
            }
        }
        
        // Rule 3d: Data classes cannot declare open members.
        if ownerSym.flags.contains(.dataType) && memberMeta.hasOpen {
            let ownerName = ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                "Data class '\(ownerName)' cannot have open members. Data classes are final by design.",
                range: memberMeta.range
            )
        }
    }

    // MARK: - Check 5: override openness validation

    private func validateOverrideOpenness(
        memberMeta: MemberMeta,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        // STDLIB-INHERIT-018: Validate that override members follow Kotlin's openness rules
        
        // Find the member symbol by looking in the owner's children
        guard let ownerSym = ctx.symbols.symbol(ownerSymbol) else { return }
        
        let memberSymbol = ctx.symbols.children(ofFQName: ownerSym.fqName).first { childID in
            guard let childSym = ctx.symbols.symbol(childID) else { return false }
            return childSym.name == memberMeta.name && 
                   (childSym.kind == .function || childSym.kind == .property)
        }
        
        guard let memberSymID = memberSymbol,
              let memberSym = ctx.symbols.symbol(memberSymID) else { return }
        
        // Check if this is an override member
        if memberMeta.hasOverride {
            // Rule: Override members are implicitly open unless marked final
            if !memberMeta.hasFinal {
                // This override member should be overridable by subclasses
                // The isMemberOverridable function already handles this logic
                // but we can add additional validation here if needed
                
                // Ensure the symbol has the overrideMember flag set
                if !memberSym.flags.contains(.overrideMember) {
                    // This would be a symbol table consistency issue
                    let memberName = ctx.interner.resolve(memberMeta.name)
                    ctx.diagnostics.error(
                        "KSWIFTK-SEMA-INTERNAL",
                        "Internal error: override member '\(memberName)' missing overrideMember flag.",
                        range: memberMeta.range
                    )
                }
            } else {
                // final override - this member cannot be further overridden
                // Ensure both flags are set correctly
                if !memberSym.flags.contains(.overrideMember) || !memberSym.flags.contains(.finalMember) {
                    let memberName = ctx.interner.resolve(memberMeta.name)
                    ctx.diagnostics.error(
                        "KSWIFTK-SEMA-INTERNAL",
                        "Internal error: final override member '\(memberName)' has incorrect flags.",
                        range: memberMeta.range
                    )
                }
            }
        }
    }

    // MARK: - Check 4: abstract override constraints

    private func validateAbstractOverrideConstraints(
        memberMeta: MemberMeta,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        // STDLIB-INHERIT-018: Validate abstract override combinations
        
        // Check 1: abstract override is only allowed in abstract classes
        if memberMeta.hasAbstract {
            guard let ownerSym = ctx.symbols.symbol(ownerSymbol) else { return }
            
            if !ownerSym.flags.contains(.abstractType) {
                let memberName = ctx.interner.resolve(memberMeta.name)
                let ownerName = ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT-OVERRIDE",
                    "'\(memberName)' cannot be abstract in non-abstract class '\(ownerName)'. Abstract members are only allowed in abstract classes.",
                    range: memberMeta.range
                )
                return
            }
            
            // Check 2: abstract override must reference an inherited declaration.
            let parent = findInheritedMember(
                named: memberMeta.name,
                for: ownerSymbol,
                symbols: ctx.symbols
            )
            if parent == nil {
                let memberName = ctx.interner.resolve(memberMeta.name)
                let ownerName = ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT-OVERRIDE",
                    "'\(memberName)' in '\(ownerName)' is marked 'abstract override' but no inherited member was found to override.",
                    range: memberMeta.range
                )
            }
        }
        
        // Check 3: final override cannot be used with abstract
        if memberMeta.hasAbstract && memberMeta.hasFinal {
            let memberName = ctx.interner.resolve(memberMeta.name)
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                "'\(memberName)' cannot be both 'abstract' and 'final'. These modifiers are mutually exclusive.",
                range: memberMeta.range
            )
        }
    }

    // MARK: - Check 2: override target is not final

    private func validateOverrideTarget(
        memberName: InternedString,
        memberRange: SourceRange,
        ownerSymbol: SymbolID,
        returnType: TypeID?,
        visibility: Visibility,
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

        if isMemberOverridable(parentSym, parent: parent) { 
            // Check return type covariance
            if let returnType = returnType {
                validateReturnTypeCovariance(
                    childReturnType: returnType,
                    parentSymbol: parentSym,
                    memberName: memberName,
                    memberRange: memberRange,
                    ctx: ctx
                )
            }
            
            // Check visibility expansion
            validateVisibilityExpansion(
                childVisibility: visibility,
                parentSymbol: parentSym,
                memberName: memberName,
                memberRange: memberRange,
                ctx: ctx
            )
            
            return 
        }

        let name = ctx.interner.resolve(memberName)
        let ownerName = ctx.interner.resolve(parent.ownerName)
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-FINAL",
            "'\(name)' in '\(ownerName)' is final and cannot be overridden.",
            range: memberRange
        )
    }

    // MARK: - Check 2a: return type covariance

    private func validateReturnTypeCovariance(
        childReturnType: TypeID,
        parentSymbol: SemanticSymbol,
        memberName: InternedString,
        memberRange: SourceRange,
        ctx: OpenFinalOverrideContext
    ) {
        guard let parentSignature = ctx.symbols.functionSignature(for: parentSymbol.id) else {
            return
        }
        let parentReturnType = parentSignature.returnType

        guard ctx.types.isSubtype(childReturnType, parentReturnType) else {
            let name = ctx.interner.resolve(memberName)
            let ownerName = ctx.interner.resolve(parentSymbol.name)
            let childType = ctx.types.renderType(childReturnType)
            let parentType = ctx.types.renderType(parentReturnType)

            ctx.diagnostics.error(
                "KSWIFTK-SEMA-OVERRIDE",
                "'\(name)' in '\(ownerName)' has return type '\(childType)', which is not a subtype of overridden return type '\(parentType)'.",
                range: memberRange
            )
            return
        }
    }

    // MARK: - Check 2b: visibility expansion

    private func validateVisibilityExpansion(
        childVisibility: Visibility,
        parentSymbol: SemanticSymbol,
        memberName: InternedString,
        memberRange: SourceRange,
        ctx: OpenFinalOverrideContext
    ) {
        let parentVisibility = parentSymbol.visibility
        
        // In Kotlin, overriding member cannot have lower visibility than parent
        // private < protected < internal < public
        if !isVisibilityExpansionAllowed(child: childVisibility, parent: parentVisibility) {
            let name = ctx.interner.resolve(memberName)
            let ownerName = ctx.interner.resolve(parentSymbol.name)
            let childVisStr = visibilityToString(childVisibility)
            let parentVisStr = visibilityToString(parentVisibility)
            
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-VISIBILITY",
                "'\(name)' in '\(ownerName)' has \(childVisStr) visibility, which is more restrictive than \(parentVisStr) visibility of overridden member.",
                range: memberRange
            )
        }
    }

    private func isVisibilityExpansionAllowed(child: Visibility, parent: Visibility) -> Bool {
        // Visibility hierarchy: private < protected < internal < public
        // Child visibility must be >= parent visibility
        let visibilityOrder: [Visibility] = [.private, .protected, .internal, .public]
        
        guard let childIndex = visibilityOrder.firstIndex(of: child),
              let parentIndex = visibilityOrder.firstIndex(of: parent) else {
            return false
        }
        
        return childIndex >= parentIndex
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
        if sym.flags.contains(.overrideMember), !sym.flags.contains(.finalMember) {
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
