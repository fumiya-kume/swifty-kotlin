import Foundation

extension DataFlowSemaPhase {
    func collectCompanionObjectHeader(
        companionDeclID: DeclID,
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        ownerType: TypeID?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let decl = ast.arena.decl(companionDeclID),
              case let .objectDecl(companionObject) = decl
        else {
            return
        }

        // Companion objects default to name "Companion" if the parsed name is empty or just "Companion"
        let companionName: InternedString
        let parsedName = interner.resolve(companionObject.name)
        if parsedName.isEmpty {
            companionName = interner.intern("Companion")
        } else {
            companionName = companionObject.name
        }

        let companionFQName = ownerFQName + [companionName]
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: companionObject.range,
            visibility: visibility(from: companionObject.modifiers),
            flags: flags(from: companionObject.modifiers)
        )
        registerAnnotations(
            for: decl,
            symbol: companionSymbol,
            declRange: companionObject.range,
            symbols: symbols,
            diagnostics: diagnostics
        )
        bindings.bindDecl(companionDeclID, symbol: companionSymbol)
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
        scope.insert(companionSymbol)

        let companionType = types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
        let companionScope = ClassMemberScope(
            parent: scope,
            symbols: symbols,
            ownerSymbol: companionSymbol,
            thisType: companionType
        )
        collectNestedTypeAliases(
            companionObject.nestedTypeAliases,
            ownerFQName: companionFQName,
            ast: ast,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner
        )
        collectMemberHeaders(
            members: MemberDeclarations(
                functions: companionObject.memberFunctions,
                properties: companionObject.memberProperties,
                nestedClasses: companionObject.nestedClasses,
                nestedObjects: companionObject.nestedObjects
            ),
            owner: OwnerContext(fqName: companionFQName, symbol: companionSymbol, type: companionType),
            ast: ast,
            symbols: symbols,
            types: types,
            bindings: bindings,
            scope: companionScope,
            diagnostics: diagnostics,
            interner: interner
        )
        if symbols.symbol(ownerSymbol)?.kind == .enumClass,
           let ownerType {
            collectSyntheticEnumCompanionMembers(
                companionSymbol: companionSymbol,
                companionFQName: companionFQName,
                enumType: ownerType,
                symbols: symbols,
                types: types,
                scope: companionScope,
                interner: interner
            )
        }
    }

    func collectNestedTypeAliases(
        _ aliases: [TypeAliasDecl],
        ownerFQName: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for alias in aliases {
            let aliasFQName = ownerFQName + [alias.name]
            checkAndReportDuplicateDeclaration(
                newKind: .typeAlias,
                fqName: aliasFQName,
                range: alias.range,
                symbols: symbols,
                diagnostics: diagnostics,
                newFlags: flags(from: alias.modifiers)
            )
            let aliasSymbol = symbols.define(
                kind: .typeAlias,
                name: alias.name,
                fqName: aliasFQName,
                declSite: alias.range,
                visibility: visibility(from: alias.modifiers),
                flags: flags(from: alias.modifiers)
            )
            let localTypeParameters = registerTypeAliasTypeParameters(
                alias.typeParams,
                aliasSymbol: aliasSymbol,
                parentFQName: aliasFQName,
                declSite: alias.range,
                symbols: symbols,
                interner: interner
            )
            if alias.underlyingType == nil {
                diagnostics.error(
                    "KSWIFTK-SEMA-0061",
                    "Type alias '\(interner.resolve(alias.name))' must have a right-hand side type.",
                    range: alias.range
                )
            } else if let resolvedUnderlying = resolveTypeRef(
                alias.underlyingType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                diagnostics: diagnostics
            ) {
                symbols.setTypeAliasUnderlyingType(resolvedUnderlying, for: aliasSymbol)
            }
        }
    }
}
