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
    let compilationModuleFQN: InternedString
}

extension DataFlowSemaPhase {
    func validateOpenFinalOverride(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        compilationModuleName: String
    ) {
        let ctx = OpenFinalOverrideContext(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            compilationModuleFQN: interner.intern(compilationModuleName)
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

        // DATA-CTOR: Validate that data class primary constructor params are all val/var.
        if case let .classDecl(classDecl) = decl,
           classDecl.modifiers.contains(.data) {
            validateDataClassConstructorParams(classDecl: classDecl, ctx: ctx)
            validateDataClassCopyVisibilityMigration(
                classDecl: classDecl,
                symbol: symbol,
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

    // MARK: - DATA-CTOR: data class primary constructor parameter validation

    private func validateDataClassConstructorParams(
        classDecl: ClassDecl,
        ctx: OpenFinalOverrideContext
    ) {
        for param in classDecl.primaryConstructorParams {
            guard !param.isProperty else { continue }
            // This parameter lacks val/var; emit error.
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-DATA-CTOR",
                "Primary constructor of data class must only have property ('val' / 'var') parameters.",
                range: classDecl.range
            )
        }
    }

    private func validateDataClassCopyVisibilityMigration(
        classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard classDecl.hasPrimaryConstructorSyntax,
              !dataClassUsesConsistentCopyVisibility(classDecl),
              !dataClassUsesExposedCopyVisibility(classDecl)
        else {
            return
        }

        let classSymbol = ctx.symbols.symbol(symbol)
        let constructorVisibility = primaryConstructorVisibility(
            for: classDecl,
            classSymbol: classSymbol
        )
        guard constructorVisibility != .public else {
            return
        }

        let className = classSymbol?.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            ?? ctx.interner.resolve(classDecl.name)
        let visibilityName = renderVisibility(constructorVisibility)
        ctx.diagnostics.warning(
            "KSWIFTK-SEMA-DATA-COPY-VISIBILITY",
            "Data class '\(className)' has a \(visibilityName) primary constructor; generated copy() remains public unless '@ConsistentCopyVisibility' or '@ExposedCopyVisibility' is applied.",
            range: classDecl.range
        )
    }

    private func renderVisibility(_ visibility: Visibility) -> String {
        switch visibility {
        case .public:
            "public"
        case .private:
            "private"
        case .internal:
            "internal"
        case .protected:
            "protected"
        }
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

            if isSubclassable(sup, interner: ctx.interner) { continue }
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

    private func isSubclassable(_ sym: SemanticSymbol, interner: StringInterner) -> Bool {
        // kotlin.Any is the root superclass and must stay subclassable even if
        // the imported metadata marks it as final.
        if sym.fqName.count == 2,
           interner.resolve(sym.fqName[0]) == "kotlin",
           interner.resolve(sym.fqName[1]) == "Any"
        {
            return true
        }
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
                  let memberSymbol = ctx.bindings.declSymbols[memberDeclID]
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
                    parameterTypes: memberMeta.parameterTypes,
                    returnType: memberMeta.returnType,
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
                    memberSymbol: memberSymbol,
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
        let parameterTypes: [TypeID]?
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
            // Only read the return type from the function signature when there
            // is an explicit return type annotation in the source. Expression-body
            // functions without an explicit annotation store `anyType` as a
            // placeholder at header-collection time (before type checking runs).
            // Using that placeholder would produce false KSWIFTK-SEMA-OVERRIDE-RETURN
            // diagnostics because `Any` is not a subtype of the parent's specific
            // return type (e.g. Unit, String). Covariance of such functions is
            // deferred until explicit annotations are present.
            let returnType: TypeID? = if fun.returnType != nil {
                ctx.bindings.declSymbols[declID]
                    .flatMap { ctx.symbols.functionSignature(for: $0)?.returnType }
            } else {
                nil
            }
            let parameterTypes = ctx.bindings.declSymbols[declID]
                .flatMap { ctx.symbols.functionSignature(for: $0)?.parameterTypes }
            return MemberMeta(
                name: fun.name,
                range: fun.range,
                hasOverride: fun.modifiers.contains(.override),
                hasOpen: fun.modifiers.contains(.open),
                parameterTypes: parameterTypes,
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
                parameterTypes: nil,
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
        guard memberMeta.hasOverride else { return }

        let parent = findInheritedMember(
            named: memberMeta.name,
            for: ownerSymbol,
            symbols: ctx.symbols,
            parameterTypes: memberMeta.parameterTypes
        )
        guard let parent else { return }
        guard let parentSym = ctx.symbols.symbol(parent.memberID) else { return }

        validateVisibilityExpansion(
            childVisibility: memberMeta.visibility,
            childOwnerSymbol: ownerSymbol,
            parentSymbol: parentSym,
            memberName: memberMeta.name,
            memberRange: memberMeta.range,
            ctx: ctx
        )
    }

    private func visibilityToString(_ visibility: Visibility) -> String {
        switch visibility {
        case .private: return "private"
        case .protected: return "protected"
        case .internal: return "internal"
        case .public: return "public"
        }
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
        parameterTypes: [TypeID]?,
        returnType: TypeID?,
        ctx: OpenFinalOverrideContext
    ) {
        let parent = findInheritedMember(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols,
            parameterTypes: parameterTypes
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
                    ownerSymbol: ownerSymbol,
                    ctx: ctx
                )
            }

            // Check exception type covariance
            validateExceptionTypeCovariance(
                memberName: memberName,
                memberRange: memberRange,
                ownerSymbol: ownerSymbol,
                parentSymbol: parentSym,
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
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard let parentSignature = ctx.symbols.functionSignature(for: parentSymbol.id) else {
            return
        }
        let parentReturnType = parentSignature.returnType

        // Skip check if this member is overloaded in the parent hierarchy.
        // With name-only lookup, findInheritedMember may match a different overload
        // than the one actually being overridden, producing false positives for valid
        // covariant overrides (e.g. base has foo(Int): Int and foo(String): String;
        // child overrides foo(String): String with return type String).
        let allParentMembers = findAllInheritedMembers(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols
        )
        guard allParentMembers.count == 1 else {
            // Multiple overloads with this name: skip covariance check to avoid
            // false positives. A future signature-aware lookup will handle this.
            return
        }

        // Enhanced covariance check for generic types
        if typeContainsAnyTypeParam(parentReturnType, types: ctx.types) ||
           typeContainsAnyTypeParam(childReturnType, types: ctx.types) {
            let parentOwnerClass = ctx.symbols.parentSymbol(for: parentSymbol.id)
            let childSignature = getFunctionMemberMatching(
                parentSignature,
                named: memberName,
                in: ownerSymbol,
                ctx: ctx
            ).flatMap { ctx.symbols.functionSignature(for: $0) }
            if !validateGenericReturnTypeCovariance(
                childReturnType: childReturnType,
                parentReturnType: parentReturnType,
                parentSignature: parentSignature,
                childSignature: childSignature,
                parentOwnerClass: parentOwnerClass,
                childOwnerClass: ownerSymbol,
                types: ctx.types,
                symbols: ctx.symbols
            ) {
                let name = ctx.interner.resolve(memberName)
                let parentReturnTypeStr = ctx.types.renderType(parentReturnType)
                let childReturnTypeStr = ctx.types.renderType(childReturnType)
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-OVERRIDE-RETURN",
                    "Override of '\(name)' has incompatible return type. "
                        + "Expected covariant relationship with '\(parentReturnTypeStr)' but found '\(childReturnTypeStr)'.",
                    range: memberRange
                )
            }
            return
        }

        // Child return type must be a subtype of parent return type (covariant return).
        guard !ctx.types.isSubtype(childReturnType, parentReturnType) else {
            return // Valid: child return type is a subtype of parent return type
        }

        let name = ctx.interner.resolve(memberName)
        let parentReturnTypeStr = ctx.types.renderType(parentReturnType)
        let childReturnTypeStr = ctx.types.renderType(childReturnType)
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-OVERRIDE-RETURN",
            "Override of '\(name)' has incompatible return type. "
                + "Expected subtype of '\(parentReturnTypeStr)' but found '\(childReturnTypeStr)'.",
            range: memberRange
        )
    }

    // MARK: - Check 2c: exception type covariance

    private func validateExceptionTypeCovariance(
        memberName: InternedString,
        memberRange: SourceRange,
        ownerSymbol: SymbolID,
        parentSymbol: SemanticSymbol,
        ctx: OpenFinalOverrideContext
    ) {
        guard let parentSignature = ctx.symbols.functionSignature(for: parentSymbol.id),
              let childSymbol = getFunctionMemberMatching(parentSignature, named: memberName, in: ownerSymbol, ctx: ctx),
              let childSignature = ctx.symbols.functionSignature(for: childSymbol) else {
            return
        }

        // Skip check if this member is overloaded in the parent hierarchy
        let allParentMembers = findAllInheritedMembers(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols
        )
        guard allParentMembers.count == 1 else {
            return
        }

        let parentExceptions = parentSignature.canThrow
        let childExceptions = childSignature.canThrow

        // Exception covariance check: child cannot throw more exceptions than parent
        if parentExceptions && !childExceptions {
            // This is valid - child throws fewer exceptions
            return
        }

        if !parentExceptions && childExceptions {
            // Child throws exceptions but parent doesn't - this violates covariance
            let name = ctx.interner.resolve(memberName)
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-OVERRIDE-EXCEPTION",
                "Override of '\(name)' cannot throw exceptions because overridden method does not throw.",
                range: memberRange
            )
        }

        // Note: Currently the FunctionSignature only tracks canThrow boolean, not specific exception types
        // When exception type information is added to FunctionSignature, we should enhance this check
        // to verify that child exception types are subtypes of parent exception types
    }

    private func validateGenericReturnTypeCovariance(
        childReturnType: TypeID,
        parentReturnType: TypeID,
        parentSignature: FunctionSignature,
        childSignature: FunctionSignature?,
        parentOwnerClass: SymbolID?,
        childOwnerClass: SymbolID,
        types: TypeSystem,
        symbols: SymbolTable
    ) -> Bool {
        guard let parentOwnerClass else {
            return validateBasicGenericReturnTypeCovariance(
                childReturnType: childReturnType,
                parentReturnType: parentReturnType,
                types: types
            )
        }

        guard let liftedParentArgs = liftedSupertypeArgs(
            from: childOwnerClass,
            to: parentOwnerClass,
            types: types,
            symbols: symbols
        ) else {
            return validateBasicGenericReturnTypeCovariance(
                childReturnType: childReturnType,
                parentReturnType: parentReturnType,
                types: types
            )
        }

        let childClassArgs = classTypeParamArgs(for: childOwnerClass, types: types)
        var substitutedParentReturn = types.substituteNominalTypeParameters(
            in: parentReturnType,
            owner: parentOwnerClass,
            ownerArgs: liftedParentArgs
        )

        if let childSignature,
           let (methodSubstitution, parentTypeVarBySymbol) = alignMethodTypeParameterSubstitution(
               parentSignature: parentSignature,
               childSignature: childSignature,
               types: types
           ),
           !methodSubstitution.isEmpty
        {
            substitutedParentReturn = types.substituteTypeParameters(
                in: substitutedParentReturn,
                substitution: methodSubstitution,
                typeVarBySymbol: parentTypeVarBySymbol
            )
        }

        let substitutedChildReturn = types.substituteNominalTypeParameters(
            in: childReturnType,
            owner: childOwnerClass,
            ownerArgs: childClassArgs
        )

        return types.isSubtype(substitutedChildReturn, substitutedParentReturn)
    }

    private func liftedSupertypeArgs(
        from childOwner: SymbolID,
        to parentOwner: SymbolID,
        types: TypeSystem,
        symbols: SymbolTable
    ) -> [TypeArg]? {
        if childOwner == parentOwner {
            return classTypeParamArgs(for: childOwner, types: types)
        }

        let childClassArgs = classTypeParamArgs(for: childOwner, types: types)
        if let lifted = types.liftedNominalSupertypeArgs(
            from: childOwner,
            childArgs: childClassArgs,
            to: parentOwner
        ) {
            return lifted
        }

        let directArgs = symbols.supertypeTypeArgs(for: childOwner, supertype: parentOwner)
        guard !directArgs.isEmpty else { return nil }
        guard !childClassArgs.isEmpty else { return directArgs }

        return directArgs.map { arg in
            substituteTypeArgForOwner(arg, owner: childOwner, ownerArgs: childClassArgs, types: types)
        }
    }

    private func classTypeParamArgs(for owner: SymbolID, types: TypeSystem) -> [TypeArg] {
        types.nominalTypeParameterSymbols(for: owner).map { symbol in
            .invariant(types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull))))
        }
    }

    private func substituteTypeArgForOwner(
        _ arg: TypeArg,
        owner: SymbolID,
        ownerArgs: [TypeArg],
        types: TypeSystem
    ) -> TypeArg {
        switch arg {
        case let .invariant(type):
            .invariant(types.substituteNominalTypeParameters(in: type, owner: owner, ownerArgs: ownerArgs))
        case let .out(type):
            .out(types.substituteNominalTypeParameters(in: type, owner: owner, ownerArgs: ownerArgs))
        case let .in(type):
            .in(types.substituteNominalTypeParameters(in: type, owner: owner, ownerArgs: ownerArgs))
        case .star:
            .star
        }
    }

    private func alignMethodTypeParameterSubstitution(
        parentSignature: FunctionSignature,
        childSignature: FunctionSignature,
        types: TypeSystem
    ) -> ([TypeVarID: TypeID], [SymbolID: TypeVarID])? {
        let parentMethodCount = parentSignature.typeParameterSymbols.count - parentSignature.classTypeParameterCount
        let childMethodCount = childSignature.typeParameterSymbols.count - childSignature.classTypeParameterCount
        guard parentMethodCount == childMethodCount else { return nil }

        let parentMethodTypeParams = Array(parentSignature.typeParameterSymbols.suffix(parentMethodCount))
        let childMethodTypeParams = Array(childSignature.typeParameterSymbols.suffix(childMethodCount))
        let parentTypeVarBySymbol = types.makeTypeVarBySymbol(parentSignature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (parentTypeParam, childTypeParam) in zip(parentMethodTypeParams, childMethodTypeParams) {
            guard let typeVar = parentTypeVarBySymbol[parentTypeParam] else { continue }
            substitution[typeVar] = types.make(.typeParam(TypeParamType(
                symbol: childTypeParam,
                nullability: .nonNull
            )))
        }
        return (substitution, parentTypeVarBySymbol)
    }

    /// Fallback for cases where inheritance type arguments cannot be resolved.
    private func validateBasicGenericReturnTypeCovariance(
        childReturnType: TypeID,
        parentReturnType: TypeID,
        types: TypeSystem
    ) -> Bool {
        let parentKind = types.kind(of: parentReturnType)
        let childKind = types.kind(of: childReturnType)

        // Case 1: Both are the same generic class with potentially different type arguments
        if case let .classType(parentClass) = parentKind,
           case let .classType(childClass) = childKind,
           parentClass.classSymbol == childClass.classSymbol {
            return validateGenericTypeArgumentCovariance(
                childArgs: childClass.args,
                parentArgs: parentClass.args,
                types: types
            )
        }

        // Case 2: Child is a subtype of parent (for non-generic cases)
        return types.isSubtype(childReturnType, parentReturnType)
    }

    private func validateGenericTypeArgumentCovariance(
        childArgs: [TypeArg],
        parentArgs: [TypeArg],
        types: TypeSystem
    ) -> Bool {
        guard childArgs.count == parentArgs.count else { return false }

        for (childArg, parentArg) in zip(childArgs, parentArgs) {
            switch (childArg, parentArg) {
            case (.out(let childType), .out(let parentType)):
                // Both are covariant: child must be subtype of parent
                if !types.isSubtype(childType, parentType) {
                    return false
                }
            case (.in(let childType), .in(let parentType)):
                // Both are contravariant: parent must be subtype of child
                if !types.isSubtype(parentType, childType) {
                    return false
                }
            case (.invariant(let childType), .invariant(let parentType)):
                // Both are invariant: types must be equal
                if childType != parentType {
                    return false
                }
            default:
                // Mixed variances: conservative approach - reject
                return false
            }
        }

        return true
    }

    /// Child functions named `memberName` in `ownerSymbol` (overload set).
    private func childFunctions(
        named memberName: InternedString,
        in ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> [SymbolID] {
        guard let ownerSym = ctx.symbols.symbol(ownerSymbol) else { return [] }
        return ctx.symbols.children(ofFQName: ownerSym.fqName).compactMap { childID -> SymbolID? in
            guard let child = ctx.symbols.symbol(childID),
                  child.name == memberName,
                  child.kind == .function
            else { return nil }
            return childID
        }
    }

    /// Pick the overriding overload in the child that matches the parent signature (Kotlin override rules).
    private func getFunctionMemberMatching(
        _ parentSignature: FunctionSignature,
        named memberName: InternedString,
        in ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> SymbolID? {
        for childID in childFunctions(named: memberName, in: ownerSymbol, ctx: ctx) {
            guard let childSig = ctx.symbols.functionSignature(for: childID) else { continue }
            if signaturesMatch(child: childSig, parent: parentSignature, ctx: ctx) {
                return childID
            }
        }
        return nil
    }

    // MARK: - Check 2b: visibility expansion

    private func validateVisibilityExpansion(
        childVisibility: Visibility,
        childOwnerSymbol: SymbolID,
        parentSymbol: SemanticSymbol,
        memberName: InternedString,
        memberRange: SourceRange,
        ctx: OpenFinalOverrideContext
    ) {
        let parentVisibility = parentSymbol.visibility

        // Enhanced visibility validation with Kotlin-specific rules

        // Rule 1: Basic visibility hierarchy check
        if !isVisibilityExpansionAllowed(child: childVisibility, parent: parentVisibility) {
            // Kotlin permits narrowing to `internal` within the same module.
            let sameModule = areSymbolsInSameModule(
                childOwnerSymbol,
                parentSymbol.id,
                ctx: ctx
            )
            let isSameModuleInternalNarrowing = sameModule
                && childVisibility == .internal
                && (parentVisibility == .public || parentVisibility == .protected)

            if !isSameModuleInternalNarrowing {
                let name = ctx.interner.resolve(memberName)
                let ownerName = resolveOwnerName(of: parentSymbol, ctx: ctx)

                if !sameModule,
                   childVisibility == .internal,
                   parentVisibility == .public || parentVisibility == .protected {
                    ctx.diagnostics.error(
                        "KSWIFTK-SEMA-VISIBILITY-MODULE",
                        "'\(name)' cannot override '\(ownerName).\(name)' with internal visibility because the overridden member is declared in another module.",
                        range: memberRange
                    )
                    return
                }

                let childVisStr = visibilityToString(childVisibility)
                let parentVisStr = visibilityToString(parentVisibility)

                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-VISIBILITY",
                    "'\(name)' cannot override '\(ownerName).\(name)' because it has \(childVisStr) visibility, which is more restrictive than the \(parentVisStr) visibility of the overridden member.",
                    range: memberRange
                )
                return
            }
        }

        // Rule 2: Special handling for interface members
        if let ownerSym = ctx.symbols.symbol(ctx.symbols.parentSymbol(for: parentSymbol.id) ?? parentSymbol.id),
           ownerSym.kind == .interface {
            // Interface members are implicitly public, but can be implemented with broader visibility
            if childVisibility == .private {
                let name = ctx.interner.resolve(memberName)
                let ownerName = ctx.interner.resolve(parentSymbol.name)
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-VISIBILITY",
                    "'\(name)' cannot implement interface member '\(ownerName).\(name)' with private visibility. Interface implementations must be at least internal.",
                    range: memberRange
                )
            }
        }

        // Rule 3: Module boundary visibility rules
        validateModuleBoundaryCompatibility(
            childVisibility: childVisibility,
            childOwnerSymbol: childOwnerSymbol,
            parentSymbol: parentSymbol,
            memberName: memberName,
            memberRange: memberRange,
            ctx: ctx
        )
    }

    private func validateModuleBoundaryCompatibility(
        childVisibility: Visibility,
        childOwnerSymbol: SymbolID,
        parentSymbol: SemanticSymbol,
        memberName: InternedString,
        memberRange: SourceRange,
        ctx: OpenFinalOverrideContext
    ) {
        guard let childModule = resolveModuleFQN(for: childOwnerSymbol, ctx: ctx),
              let parentModule = resolveModuleFQN(for: parentSymbol.id, ctx: ctx)
        else {
            return
        }

        guard childModule != parentModule else {
            return
        }

        let name = ctx.interner.resolve(memberName)
        let parentVisibility = parentSymbol.visibility

        if parentVisibility == .internal {
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-VISIBILITY-MODULE",
                "'\(name)' cannot override internal member from another module.",
                range: memberRange
            )
            return
        }

        if childVisibility == .internal,
           parentVisibility == .public || parentVisibility == .protected {
            let ownerName = resolveOwnerName(of: parentSymbol, ctx: ctx)
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-VISIBILITY-MODULE",
                "'\(name)' cannot override '\(ownerName).\(name)' with internal visibility because the overridden member is declared in another module.",
                range: memberRange
            )
        }
    }

    private func resolveOwnerName(of member: SemanticSymbol, ctx: OpenFinalOverrideContext) -> String {
        if let ownerID = ctx.symbols.parentSymbol(for: member.id),
           let owner = ctx.symbols.symbol(ownerID) {
            return ctx.interner.resolve(owner.name)
        }
        return ctx.interner.resolve(member.name)
    }

    private func resolveModuleFQN(
        for symbolID: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> InternedString? {
        var current: SymbolID? = symbolID
        while let id = current {
            if let module = ctx.symbols.moduleFQN(for: id) {
                return module
            }
            // sourceFileID がある = コンパイル対象ソースのシンボル。
            // assignCompilationModuleFQNames が設定を漏らした場合のフォールバック。
            if ctx.symbols.sourceFileID(for: id) != nil {
                return ctx.compilationModuleFQN
            }
            current = ctx.symbols.parentSymbol(for: id)
        }
        return nil
    }

    private func areSymbolsInSameModule(
        _ lhs: SymbolID,
        _ rhs: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        guard let lhsModule = resolveModuleFQN(for: lhs, ctx: ctx),
              let rhsModule = resolveModuleFQN(for: rhs, ctx: ctx)
        else {
            return false
        }
        return lhsModule == rhsModule
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
        memberSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        let name = ctx.interner.resolve(memberName)

        // Enhanced override detection with signature-aware matching

        // Find all potential parent members that could be overridden
        let allParentMembers = findAllInheritedMembers(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols
        )

        guard !allParentMembers.isEmpty else { return }

        // Filter to only overridable members
        let overridableParents = allParentMembers.filter { parent in
            guard let parentSym = ctx.symbols.symbol(parent.memberID) else { return false }
            return isMemberOverridable(parentSym, parent: parent)
        }

        guard !overridableParents.isEmpty else { return }

        // Match the inherited member against the declaration currently being
        // validated. Looking at every child overload with this name makes an
        // unrelated overload appear to implement the interface member (for
        // example, StringBuilder.append(Int) after StringBuilder.append(Char)
        // is declared as an Appendable override).
        let matchingParents: [OFOInheritedMember]
        if let childSignature = ctx.symbols.functionSignature(for: memberSymbol) {
            matchingParents = overridableParents.filter { parent in
                guard let parentSignature = ctx.symbols.functionSignature(for: parent.memberID) else {
                    return false
                }
                // Kotlin member overrides require equal parameter types. The
                // general compatibility helper intentionally accepts
                // contravariant parameters for other checks, which would
                // incorrectly classify append(Any?) as Appendable.append(CharSequence?).
                return childSignature.parameterTypes == parentSignature.parameterTypes
                    && childSignature.isSuspend == parentSignature.isSuspend
                    && ctx.types.isSubtype(childSignature.returnType, parentSignature.returnType)
            }
        } else if ctx.symbols.symbol(memberSymbol)?.kind == .property {
            matchingParents = overridableParents.filter { parent in
                ctx.symbols.symbol(parent.memberID)?.kind == .property
            }
        } else {
            matchingParents = []
        }

        guard !matchingParents.isEmpty else { return }

        // Special handling for interface implementations
        if let ownerSym = ctx.symbols.symbol(ownerSymbol), ownerSym.kind == .class {
            // Check if this is implementing an interface method
            let interfaceParents = matchingParents.filter { $0.ownerIsInterface }
            if !interfaceParents.isEmpty {
                // For interface implementations with matching signature, require override modifier.
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-OVERRIDE",
                    "'\(name)' implements interface member and needs 'override' modifier.",
                    range: memberRange
                )
                return
            }
        }

        // For class inheritance, check if this actually overrides a parent member
        // Use improved signature matching to avoid false positives with overloads
        if let ownerSym = ctx.symbols.symbol(ownerSymbol), ownerSym.kind == .class {
            let classParents = matchingParents.filter { !$0.ownerIsInterface }
            if !classParents.isEmpty {
                let parentName = ctx.interner.resolve(classParents.first!.ownerName)
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-OVERRIDE",
                    "'\(name)' hides member of supertype '\(parentName)' "
                        + "and needs 'override' modifier.",
                    range: memberRange
                )
                return
            }
        }
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
        symbols: SymbolTable,
        parameterTypes: [TypeID]? = nil
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
                guard isMatch, child.name == memberName else {
                    continue
                }
                // Function overloads must be matched by their parameter types;
                // name-only lookup can select a synthetic range overload before
                // the real member being overridden.
                if let parameterTypes {
                    guard child.kind == .function,
                          symbols.functionSignature(for: childID)?.parameterTypes == parameterTypes
                    else {
                        continue
                    }
                }
                if isMatch {
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

    private func typeContainsAnyTypeParam(_ typeID: TypeID, types: TypeSystem) -> Bool {
        switch types.kind(of: typeID) {
        case .typeParam:
            return true
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return typeContainsAnyTypeParam(inner, types: types)
                case .star:
                    return false
                }
            }
        case let .functionType(ft):
            if ft.contextReceivers.contains(where: { typeContainsAnyTypeParam($0, types: types) }) { return true }
            if let receiver = ft.receiver, typeContainsAnyTypeParam(receiver, types: types) { return true }
            if ft.params.contains(where: { typeContainsAnyTypeParam($0, types: types) }) { return true }
            return typeContainsAnyTypeParam(ft.returnType, types: types)
        case let .intersection(parts):
            return parts.contains { typeContainsAnyTypeParam($0, types: types) }
        case let .kClassType(kct):
            return typeContainsAnyTypeParam(kct.argument, types: types)
        default:
            return false
        }
    }

    private func findAllInheritedMembers(
        named memberName: InternedString,
        for classSymbol: SymbolID,
        symbols: SymbolTable
    ) -> [OFOInheritedMember] {
        var visited: Set<SymbolID> = [classSymbol]
        var queue = symbols.directSupertypes(for: classSymbol)
        var results: [OFOInheritedMember] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            guard let sym = symbols.symbol(current) else { continue }

            var foundAtThisLevel = false
            for childID in symbols.children(ofFQName: sym.fqName) {
                guard let child = symbols.symbol(childID) else { continue }
                let isMatch = child.kind == .function || child.kind == .property
                if isMatch, child.name == memberName {
                    results.append(OFOInheritedMember(
                        memberID: childID,
                        ownerName: sym.name,
                        ownerIsInterface: sym.kind == .interface
                    ))
                    foundAtThisLevel = true
                }
            }

            // If this class defines the member, do not traverse its ancestors:
            // ancestor definitions are earlier overrides of the same logical member,
            // not separate overloads.  Continuing upward would inflate the count
            // and cause the guard at the call-site to skip the covariance check.
            if !foundAtThisLevel {
                queue.append(contentsOf: symbols.directSupertypes(for: current))
            }
        }
        return results
    }

    private func signaturesMatch(child: FunctionSignature, parent: FunctionSignature, ctx: OpenFinalOverrideContext) -> Bool {
        // Check parameter count
        guard child.parameterTypes.count == parent.parameterTypes.count else {
            return false
        }

        // Check parameter types (covariant for return, contravariant for parameters)
        for (childParam, parentParam) in zip(child.parameterTypes, parent.parameterTypes) {
            // swiftlint:disable:next for_where
            if !ctx.types.isSubtype(parentParam, childParam) {
                return false
            }
        }

        // Check return type (covariant)
        if !ctx.types.isSubtype(child.returnType, parent.returnType) {
            return false
        }

        // Check other signature aspects
        return child.isSuspend == parent.isSuspend
    }
}
