
struct MemberDeclarations {
    let functions: [DeclID]
    let properties: [DeclID]
    let nestedClasses: [DeclID]
    let nestedObjects: [DeclID]
}

struct OwnerContext {
    let fqName: [InternedString]
    let symbol: SymbolID
    let type: TypeID
}

extension DataFlowSemaPhase {
    func collectMemberHeaders(
        members: MemberDeclarations,
        owner: OwnerContext,
        sourceFileID: FileID,
        ctx: CompilationContext,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        classTypeParameterSymbols: [SymbolID] = [],
        classLocalTypeParameters: [InternedString: SymbolID] = [:]
    ) {
        let sourceManager = ctx.sourceManager
        let sourceFile = ast.files.first { $0.fileID == sourceFileID }
        let sourcePackageFQName = sourceFile?.packageFQName
        let sourceImports = sourceFile?.imports ?? []
        let ownerFQName = owner.fqName
        let ownerSymbol = owner.symbol
        let ownerType = owner.type
        let anyType = types.anyType
        let unitType = types.unitType

        // Nested class/object symbols must exist before sibling member
        // signatures are resolved, since a function's parameter/return type
        // may reference a type nested in this same body (e.g. `PaddingOption`
        // nested in `Base64`, referenced by `withPadding(option: PaddingOption)`).
        for declID in members.nestedClasses {
            collectNestedClassOrInterfaceHeader(
                declID: declID,
                ownerFQName: ownerFQName,
                ownerSymbol: ownerSymbol,
                sourceFileID: sourceFileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: scope,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        for declID in members.nestedObjects {
            collectNestedObjectHeader(
                declID: declID,
                ownerFQName: ownerFQName,
                ownerSymbol: ownerSymbol,
                sourceFileID: sourceFileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: scope,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        for declID in members.functions {
            guard let decl = ast.arena.decl(declID),
                  case let .funDecl(funDecl) = decl
            else {
                continue
            }
            let memberFQName = ownerFQName + [funDecl.name]
            var memberFlags = flags(from: funDecl.modifiers)
            checkAndReportDuplicateDeclaration(
                newKind: .function,
                fqName: memberFQName,
                range: funDecl.range,
                symbols: symbols,
                diagnostics: diagnostics,
                newFlags: memberFlags
            )
            // Kotlin: interface functions without a body are implicitly abstract.
            if symbols.symbol(ownerSymbol)?.kind == .interface, funDecl.body == .unit {
                memberFlags.insert(.abstractType)
            }

            // STDLIB-CLASS-010: Abstract functions cannot be private
            if funDecl.modifiers.contains(.abstract) && funDecl.modifiers.contains(.private) {
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Abstract function '\(interner.resolve(funDecl.name))' cannot be private.",
                    range: funDecl.range
                )
            }

            // STDLIB-CLASS-010: Abstract functions cannot have a body
            if funDecl.modifiers.contains(.abstract) && funDecl.body != .unit {
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Abstract function '\(interner.resolve(funDecl.name))' cannot have a body.",
                    range: funDecl.range
                )
            }

            // STDLIB-CLASS-010: Check for conflicting modifiers
            if funDecl.modifiers.contains(.abstract) && funDecl.modifiers.contains(.final) {
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Function '\(interner.resolve(funDecl.name))' cannot be both 'abstract' and 'final'.",
                    range: funDecl.range
                )
            }
            let memberSymbol: SymbolID
            if let existingSyntheticFunction = reusableSyntheticMemberFunctionSymbol(
                fqName: memberFQName,
                ownerSymbol: ownerSymbol,
                ownerFQName: ownerFQName,
                valueParamCount: funDecl.valueParams.count,
                expectedVisibility: visibility(from: funDecl.modifiers),
                sourceFileID: sourceFileID,
                sourceManager: sourceManager,
                symbols: symbols,
                interner: interner
            ) {
                memberSymbol = existingSyntheticFunction
                symbols.removeFlags(.synthetic, for: memberSymbol)
                // Clear placeholder-only flags so the source declaration's modifiers
                // fully determine the final symbol state; memberFlags will re-add any
                // flags that the bundled declaration actually declares.
                symbols.removeFlags([.abstractType, .static, .finalMember, .overrideMember], for: memberSymbol)
                symbols.insertFlags(memberFlags, for: memberSymbol)
                // SequenceScope's yield methods are rewritten by the builder
                // lowering pass, so the bundled declarations must not retain
                // the synthetic runtime bridge. Other bundled members may be
                // intentionally retained runtime bridges (for example the
                // Collection interface methods), so do not clear them globally.
                if ownerFQName.map(interner.resolve) == ["kotlin", "sequences", "SequenceScope"] {
                    symbols.clearExternalLinkName(for: memberSymbol)
                }
                symbols.setDeclSite(funDecl.range, for: memberSymbol)
            } else {
                memberSymbol = symbols.define(
                    kind: .function,
                    name: funDecl.name,
                    fqName: memberFQName,
                    declSite: funDecl.range,
                    visibility: visibility(from: funDecl.modifiers),
                    flags: memberFlags
                )
            }
            symbols.setSourceFileID(sourceFileID, for: memberSymbol)
            diagnoseReservedExternalFunctionUse(
                funDecl,
                sourceFileID: sourceFileID,
                sourceManager: sourceManager,
                diagnostics: diagnostics
            )
            registerAnnotations(
                for: decl,
                symbol: memberSymbol,
                declRange: funDecl.range,
                sourceFileID: sourceFileID,
                sourceManager: sourceManager,
                symbols: symbols,
                diagnostics: diagnostics
            )
            bindings.bindDecl(declID, symbol: memberSymbol)
            symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
            scope.insert(memberSymbol)

            let localNamespaceFQName = memberFQName + [interner.intern("$\(memberSymbol.rawValue)")]
            let typeParamResult = collectFunctionTypeParameters(
                funDecl.typeParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: funDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner, isInline: funDecl.isInline,
                diagnostics: diagnostics
            )

            // Merge class type parameters with function's own type parameters.
            // Function params shadow class params if names collide.
            var mergedLocalTypeParameters = classLocalTypeParameters
            for (key, value) in typeParamResult.localTypeParameters {
                mergedLocalTypeParameters[key] = value
            }

            let params = collectValueParameters(
                funDecl.valueParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: funDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner,
                localTypeParameters: mergedLocalTypeParameters,
                relativeOwnerFQName: ownerFQName,
                currentPackageFQName: sourcePackageFQName,
                imports: sourceImports,
                diagnostics: diagnostics,
                fallbackType: anyType
            )

            let returnType: TypeID = if let explicit = resolveTypeRef(
                funDecl.returnType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: mergedLocalTypeParameters,
                relativeOwnerFQName: ownerFQName,
                currentPackageFQName: sourcePackageFQName,
                imports: sourceImports,
                diagnostics: diagnostics,
                usageRange: funDecl.range
            ) {
                explicit
            } else {
                switch funDecl.body {
                case .unit, .block:
                    unitType
                case .expr:
                    anyType
                }
            }

            // Include class type parameter symbols so the overload resolver can
            // infer them from the receiver type arguments.
            let allTypeParameterSymbols = classTypeParameterSymbols + typeParamResult.typeParameterSymbols
            let classUpperBounds: [[TypeID]] = classTypeParameterSymbols.map {
                symbols.typeParameterUpperBounds(for: $0)
            }
            let memberUpperBounds: [[TypeID]] = classUpperBounds + typeParamResult.typeParameterSymbols.map {
                symbols.typeParameterUpperBounds(for: $0)
            }
            // Offset reified indices by the number of prepended class type params
            // so they still point at the correct function-own type parameters.
            let classTPCount = classTypeParameterSymbols.count
            let offsetReifiedIndices: Set<Int> = classTPCount == 0
                ? typeParamResult.reifiedIndices
                : Set(typeParamResult.reifiedIndices.map { $0 + classTPCount })
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: params.paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: params.paramSymbols,
                    valueParameterHasDefaultValues: params.paramHasDefaultValues,
                    valueParameterIsVararg: params.paramIsVararg,
                    valueParameterAllowsNonLocalReturn: params.paramAllowsNonLocalReturn,
                    typeParameterSymbols: allTypeParameterSymbols,
                    reifiedTypeParameterIndices: offsetReifiedIndices,
                    typeParameterUpperBoundsList: memberUpperBounds,
                    classTypeParameterCount: classTPCount
                ),
                for: memberSymbol
            )
            attachUuidSourceMigrationBridgeIfNeeded(
                to: memberSymbol,
                fqName: memberFQName,
                sourceFileID: sourceFileID,
                ctx: ctx,
                symbols: symbols,
                interner: interner
            )
            checkAndReportJVMErasedCallableConflict(
                for: memberSymbol,
                fqName: memberFQName,
                range: funDecl.range,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics
            )
        }

        for declID in members.properties {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            let memberFQName = ownerFQName + [propertyDecl.name]
            var propertyFlags = flags(from: propertyDecl.modifiers)
            let reusableSyntheticProperty = reusableSyntheticMemberPropertySymbol(
                fqName: memberFQName,
                ownerSymbol: ownerSymbol,
                ownerFQName: ownerFQName,
                expectedVisibility: visibility(from: propertyDecl.modifiers),
                sourceFileID: sourceFileID,
                sourceManager: sourceManager,
                symbols: symbols,
                interner: interner
            )
            if reusableSyntheticProperty == nil {
                checkAndReportDuplicateDeclaration(
                    newKind: .property,
                    fqName: memberFQName,
                    range: propertyDecl.range,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    newFlags: propertyFlags
                )
            }

            // STDLIB-CLASS-010: Abstract properties cannot have initializers
            if propertyDecl.modifiers.contains(.abstract) && propertyDecl.initializer != nil {
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Abstract property '\(interner.resolve(propertyDecl.name))' cannot have an initializer.",
                    range: propertyDecl.range
                )
            }

            // STDLIB-CLASS-010: Abstract properties cannot be private
            if propertyDecl.modifiers.contains(.abstract) && propertyDecl.modifiers.contains(.private) {
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Abstract property '\(interner.resolve(propertyDecl.name))' cannot be private.",
                    range: propertyDecl.range
                )
            }

            // STDLIB-CLASS-010: Check for conflicting modifiers
            if propertyDecl.modifiers.contains(.abstract) && propertyDecl.modifiers.contains(.final) {
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Property '\(interner.resolve(propertyDecl.name))' cannot be both 'abstract' and 'final'.",
                    range: propertyDecl.range
                )
            }

            // STDLIB-CLASS-010: Abstract properties cannot have explicit backing fields
            if propertyDecl.modifiers.contains(.abstract) && propertyDecl.explicitBackingField != nil {
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Abstract property '\(interner.resolve(propertyDecl.name))' cannot have an explicit backing field.",
                    range: propertyDecl.range
                )
            }

            // STDLIB-CLASS-010: Abstract properties cannot have delegate expressions
            if propertyDecl.modifiers.contains(.abstract) && propertyDecl.delegateExpression != nil {
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Abstract property '\(interner.resolve(propertyDecl.name))' cannot have a delegate expression.",
                    range: propertyDecl.range
                )
            }

            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }

            // Kotlin: interface properties without getter/setter body are implicitly abstract.
            // Properties with custom accessors (getter/setter) are concrete; interfaces
            // cannot hold per-instance state, so initializers and delegate expressions
            // are rejected outright (matches kotlinc's "property initializers in
            // interfaces are prohibited" / "delegated properties in interfaces are
            // prohibited").
            if symbols.symbol(ownerSymbol)?.kind == .interface {
                let hasCustomAccessor = propertyDecl.getter != nil || propertyDecl.setter != nil
                let hasInitializer = propertyDecl.initializer != nil
                let hasDelegate = propertyDecl.delegateExpression != nil
                if hasInitializer {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0303",
                        "Property initializers in interfaces are prohibited.",
                        range: propertyDecl.range
                    )
                }
                if hasDelegate {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0304",
                        "Delegated properties in interfaces are prohibited.",
                        range: propertyDecl.range
                    )
                }
                // A rejected initializer/delegate still provides no real accessor
                // body, so keep treating the property as abstract for override
                // checking (`collectInheritedAbstractMembers` in Inheritance.swift)
                // instead of silently letting implementing classes skip overriding it.
                if !hasCustomAccessor {
                    propertyFlags.insert(.abstractType)
                }
            }
            let memberSymbol: SymbolID
            if let reusableSyntheticProperty {
                memberSymbol = reusableSyntheticProperty
                symbols.removeFlags(.synthetic, for: memberSymbol)
                symbols.removeFlags([.abstractType, .static, .finalMember, .overrideMember, .mutable], for: memberSymbol)
                symbols.insertFlags(propertyFlags, for: memberSymbol)
                symbols.setDeclSite(propertyDecl.range, for: memberSymbol)
            } else {
                memberSymbol = symbols.define(
                    kind: .property,
                    name: propertyDecl.name,
                    fqName: memberFQName,
                    declSite: propertyDecl.range,
                    visibility: visibility(from: propertyDecl.modifiers),
                    flags: propertyFlags
                )
            }
            symbols.setSourceFileID(sourceFileID, for: memberSymbol)
            registerAnnotations(
                for: decl,
                symbol: memberSymbol,
                declRange: propertyDecl.range,
                sourceFileID: sourceFileID,
                sourceManager: sourceManager,
                symbols: symbols,
                diagnostics: diagnostics
            )
            bindings.bindDecl(declID, symbol: memberSymbol)
            symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
            scope.insert(memberSymbol)

            // STDLIB-CLASS-010: Abstract properties cannot have getter/setter bodies
            if propertyDecl.modifiers.contains(.abstract) {
                if let getter = propertyDecl.getter, getter.body != .unit {
                    diagnostics.error(
                        "KSWIFTK-SEMA-ABSTRACT",
                        "Abstract property '\(interner.resolve(propertyDecl.name))' cannot have a getter body.",
                        range: getter.range
                    )
                }
                if let setter = propertyDecl.setter, setter.body != .unit {
                    diagnostics.error(
                        "KSWIFTK-SEMA-ABSTRACT",
                        "Abstract property '\(interner.resolve(propertyDecl.name))' cannot have a setter body.",
                        range: setter.range
                    )
                }
            }

            // Use class type parameters for resolving member property types
            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: classLocalTypeParameters,
                relativeOwnerFQName: ownerFQName,
                currentPackageFQName: sourcePackageFQName,
                imports: sourceImports,
                diagnostics: diagnostics,
                usageRange: propertyDecl.range
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: memberSymbol)

            if let getter = propertyDecl.getter, getter.body != .unit {
                symbols.setPropertyHasCustomGetter(true, for: memberSymbol)
            }

            validateConstPropertyDeclaration(
                propertyDecl,
                propertySymbol: memberSymbol,
                resolvedType: resolvedType,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics
            )

            // Materialize a backing field symbol for properties with custom accessors
            // (Kotlin `field` identifier in getter/setter bodies) or explicit
            // backing field declarations (Kotlin 2.0 `field = expr`).
            // Simple properties with only an initializer don't need a separate
            // backing field — the property symbol IS the storage.
            // Getter-only computed properties (`val x: Int get() = expr`) never
            // need a backing field because they have no storage — the getter
            // body is evaluated on every access.
            // STDLIB-CLASS-010: Abstract properties cannot have backing fields.
            // Interfaces never need a backing field either — properties in an
            // interface have no instance state of their own (KIR lowering
            // suppresses storage emission for them; keep the symbol table
            // consistent so `field` bindings aren't wired up to a nonexistent
            // field for interface accessor bodies).
            let isAbstractProperty = propertyFlags.contains(.abstractType)
            let isInterfaceOwner = symbols.symbol(ownerSymbol)?.kind == .interface
            let hasExplicitBackingField = propertyDecl.explicitBackingField != nil
            let isGetterOnlyComputed = propertyDecl.getter != nil
                && propertyDecl.setter == nil
                && propertyDecl.initializer == nil
                && !hasExplicitBackingField
            let needsBackingField = !isAbstractProperty && !isInterfaceOwner && (
                hasExplicitBackingField
                || (!isGetterOnlyComputed
                    && (propertyDecl.getter != nil || propertyDecl.setter != nil))
            )
            if needsBackingField, propertyDecl.delegateExpression == nil {
                let fieldName = interner.intern("$backing_\(interner.resolve(propertyDecl.name))")
                let fieldFQName = ownerFQName + [fieldName]
                let backingFieldSymbol = symbols.define(
                    kind: .backingField,
                    name: fieldName,
                    fqName: fieldFQName,
                    declSite: propertyDecl.range,
                    visibility: .private,
                    flags: propertyDecl.isVar ? [.mutable] : []
                )
                symbols.setParentSymbol(ownerSymbol, for: backingFieldSymbol)
                // When an explicit backing field declares its own type, use that
                // type for the backing field symbol instead of the property type.
                let backingFieldType: TypeID
                if let explicitField = propertyDecl.explicitBackingField,
                   let explicitType = explicitField.type
                {
                    backingFieldType = resolveTypeRef(
                        explicitType,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        localTypeParameters: classLocalTypeParameters,
                        relativeOwnerFQName: ownerFQName,
                        currentPackageFQName: sourcePackageFQName,
                        imports: sourceImports,
                        diagnostics: diagnostics,
                        usageRange: propertyDecl.range
                    ) ?? resolvedType
                } else {
                    backingFieldType = resolvedType
                }
                symbols.setPropertyType(backingFieldType, for: backingFieldSymbol)
                symbols.setBackingFieldSymbol(backingFieldSymbol, for: memberSymbol)
            }

            // Create a delegate storage symbol for properties with `by` delegation.
            // This symbol tracks the delegate instance so that KIR lowering can
            // synthesise getValue/setValue accessor calls.
            // STDLIB-CLASS-010: Abstract properties cannot have delegate expressions
            if propertyDecl.delegateExpression != nil && !propertyDecl.modifiers.contains(.abstract) {
                let delegateStorageName = interner.intern("$delegate_\(interner.resolve(propertyDecl.name))")
                let delegateStorageFQName = ownerFQName + [delegateStorageName]
                let delegateStorageSymbol = symbols.define(
                    kind: .field,
                    name: delegateStorageName,
                    fqName: delegateStorageFQName,
                    declSite: propertyDecl.range,
                    visibility: .private,
                    flags: []
                )
                symbols.setParentSymbol(ownerSymbol, for: delegateStorageSymbol)
                symbols.setDelegateStorageSymbol(delegateStorageSymbol, for: memberSymbol)
            }
        }
    }

    private func collectNestedDeclarationHeader(
        kind: SymbolKind,
        name: InternedString,
        fqName: [InternedString],
        declSite: SourceRange,
        visibility: Visibility,
        flags: SymbolFlags,
        duplicateCheckFlags: SymbolFlags,
        ownerSymbol: SymbolID,
        sourceFileID: FileID,
        sourceManager: SourceManager,
        declID: DeclID,
        decl: Decl,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        bindings: BindingTable,
        scope: Scope,
        ast: ASTModule,
        interner: StringInterner
    ) -> SymbolID {
        let reusableSyntheticSymbol: SymbolID? = {
            guard let file = ast.files.first(where: { $0.fileID == sourceFileID }) else {
                return nil
            }
            return reusableSyntheticDeclarationSymbol(
                kind: kind,
                fqName: fqName,
                declarationFlags: duplicateCheckFlags,
                file: file,
                sourceManager: sourceManager,
                symbols: symbols
            )
        }()
        if reusableSyntheticSymbol == nil {
            checkAndReportDuplicateDeclaration(
                newKind: kind,
                fqName: fqName,
                range: declSite,
                symbols: symbols,
                diagnostics: diagnostics,
                newFlags: duplicateCheckFlags
            )
        }
        let nestedSymbol: SymbolID
        if let reusableSyntheticSymbol {
            nestedSymbol = reusableSyntheticSymbol
            symbols.removeFlags(.synthetic, for: nestedSymbol)
        } else {
            nestedSymbol = symbols.define(
                kind: kind,
                name: name,
                fqName: fqName,
                declSite: declSite,
                visibility: visibility,
                flags: flags
            )
        }
        symbols.setSourceFileID(sourceFileID, for: nestedSymbol)
        registerAnnotations(
            for: decl,
            symbol: nestedSymbol,
            declRange: declSite,
            sourceFileID: sourceFileID,
            sourceManager: sourceManager,
            symbols: symbols,
            diagnostics: diagnostics
        )
        bindings.bindDecl(declID, symbol: nestedSymbol)
        symbols.setParentSymbol(ownerSymbol, for: nestedSymbol)
        scope.insert(nestedSymbol)
        return nestedSymbol
    }

    private func collectNestedClassOrInterfaceHeader(
        declID: DeclID,
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        sourceFileID: FileID,
        ctx: CompilationContext,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let sourceManager = ctx.sourceManager
        guard let decl = ast.arena.decl(declID) else {
            return
        }
        let sourceFile = ast.files.first { $0.fileID == sourceFileID }
        let sourcePackageFQName = sourceFile?.packageFQName
        let sourceImports = sourceFile?.imports ?? []
        let anyType = types.anyType
        switch decl {
        case let .classDecl(nestedClass):
            let nestedFQName = ownerFQName + [nestedClass.name]
            let nestedClassKind = classSymbolKind(for: nestedClass)
            let nestedClassFlags = flags(from: nestedClass.modifiers)
            let nestedSymbol = collectNestedDeclarationHeader(
                kind: nestedClassKind,
                name: nestedClass.name,
                fqName: nestedFQName,
                declSite: nestedClass.range,
                visibility: visibility(from: nestedClass.modifiers),
                flags: nestedClassFlags,
                duplicateCheckFlags: nestedClassFlags,
                ownerSymbol: ownerSymbol,
                sourceFileID: sourceFileID,
                sourceManager: sourceManager,
                declID: declID,
                decl: decl,
                symbols: symbols,
                diagnostics: diagnostics,
                bindings: bindings,
                scope: scope,
                ast: ast,
                interner: interner
            )

            if !nestedClass.typeParams.isEmpty {
                types.setNominalTypeParameterVariances(
                    nestedClass.typeParams.map(\.variance),
                    for: nestedSymbol
                )
            }
            let nestedTypeParamResult = registerNominalTypeParameters(
                nestedClass.typeParams,
                ownerSymbol: nestedSymbol,
                fqName: nestedFQName,
                namespacePrefix: "$class",
                declSite: nestedClass.range,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            )
            let nestedTypeParamSymbols = nestedTypeParamResult.symbols
            let nestedLocalTypeParameters = nestedTypeParamResult.localMap
            let nestedTypeArgs: [TypeArg] = nestedTypeParamSymbols.map { tpSymbol in
                TypeArg.invariant(types.make(.typeParam(TypeParamType(symbol: tpSymbol))))
            }
            let nestedType = types.make(.classType(ClassType(classSymbol: nestedSymbol, args: nestedTypeArgs, nullability: .nonNull)))
            let nestedScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: nestedSymbol,
                thisType: nestedType
            )

            collectNestedTypeAliases(
                nestedClass.nestedTypeAliases,
                ownerFQName: nestedFQName,
                sourceFileID: sourceFileID,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )

            // Nested class/object headers must be collected before the primary
            // constructor parameter types are resolved, because those parameter
            // types (or their default values) may reference a nested type
            // (e.g. `annotation class Marker(val level: Level = Level.ERROR)`).
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: [],
                    properties: [],
                    nestedClasses: nestedClass.nestedClasses,
                    nestedObjects: nestedClass.nestedObjects
                ),
                owner: OwnerContext(fqName: nestedFQName, symbol: nestedSymbol, type: nestedType),
                sourceFileID: sourceFileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: nestedScope,
                diagnostics: diagnostics,
                interner: interner,
                classTypeParameterSymbols: nestedTypeParamSymbols,
                classLocalTypeParameters: nestedLocalTypeParameters
            )

            let ctorName = interner.intern("<init>")
            let nestedCtorFQName = nestedFQName + [ctorName]
            let nestedHasPrimaryCtorSyntax = nestedClass.hasPrimaryConstructorSyntax
            let nestedHasSecondaryCtors = !nestedClass.secondaryConstructors.isEmpty
            if nestedHasPrimaryCtorSyntax || !nestedHasSecondaryCtors {
                let nestedPrimaryCtorVisibilityDetail = primaryConstructorVisibilityDetail(
                    for: nestedClass,
                    classKind: nestedClassKind,
                    declarationVisibility: visibility(from: nestedClass.modifiers)
                )
                let nestedPrimaryCtorSymbol = symbols.define(
                    kind: .constructor,
                    name: nestedClass.name,
                    fqName: nestedCtorFQName,
                    declSite: nestedClass.range,
                    visibility: nestedPrimaryCtorVisibilityDetail.visibility,
                    flags: nestedPrimaryCtorVisibilityDetail.isInheritedFromOwner ? [.constructorVisibilityInherited] : []
                )
                nestedScope.insert(nestedPrimaryCtorSymbol)
                symbols.setParentSymbol(nestedSymbol, for: nestedPrimaryCtorSymbol)
                do {
                    let localNamespaceFQName = nestedCtorFQName + [interner.intern("$\(nestedPrimaryCtorSymbol.rawValue)")]
                    let params = collectValueParameters(
                        nestedClass.primaryConstructorParams,
                        localNamespaceFQName: localNamespaceFQName,
                        declSite: nestedClass.range,
                        ast: ast, symbols: symbols, types: types,
                        interner: interner,
                        localTypeParameters: nestedLocalTypeParameters,
                        relativeOwnerFQName: nestedFQName,
                        currentPackageFQName: sourcePackageFQName,
                        imports: sourceImports,
                        diagnostics: diagnostics,
                        fallbackType: anyType
                    )
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: nestedType,
                            parameterTypes: params.paramTypes,
                            returnType: nestedType,
                            valueParameterSymbols: params.paramSymbols,
                            valueParameterHasDefaultValues: params.paramHasDefaultValues,
                            valueParameterIsVararg: params.paramIsVararg,
                            valueParameterAllowsNonLocalReturn: params.paramAllowsNonLocalReturn,
                            typeParameterSymbols: nestedTypeParamSymbols,
                            classTypeParameterCount: nestedTypeParamSymbols.count
                        ),
                        for: nestedPrimaryCtorSymbol
                    )
                }
            }
            for (ctorIndex, secondaryCtor) in nestedClass.secondaryConstructors.enumerated() {
                let secCtorVisibilityDetail = constructorVisibilityDetail(
                    explicitModifiers: secondaryCtor.modifiers,
                    classKind: nestedClassKind,
                    isSealedClass: nestedClass.modifiers.contains(.sealed),
                    declarationVisibility: visibility(from: nestedClass.modifiers)
                )
                let secCtorSymbol = symbols.define(
                    kind: .constructor,
                    name: nestedClass.name,
                    fqName: nestedCtorFQName,
                    declSite: secondaryCtor.range,
                    visibility: secCtorVisibilityDetail.visibility,
                    flags: secCtorVisibilityDetail.isInheritedFromOwner ? [.constructorVisibilityInherited] : []
                )
                nestedScope.insert(secCtorSymbol)
                symbols.setParentSymbol(nestedSymbol, for: secCtorSymbol)
                let localNamespaceFQName = nestedCtorFQName + [interner.intern("$sec\(ctorIndex)_\(secCtorSymbol.rawValue)")]
                let params = collectValueParameters(
                    secondaryCtor.valueParams,
                    localNamespaceFQName: localNamespaceFQName,
                    declSite: secondaryCtor.range,
                    ast: ast, symbols: symbols, types: types,
                    interner: interner,
                    localTypeParameters: nestedLocalTypeParameters,
                    relativeOwnerFQName: nestedFQName,
                    currentPackageFQName: sourcePackageFQName,
                    imports: sourceImports,
                    diagnostics: diagnostics,
                    fallbackType: anyType
                )
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: nestedType,
                        parameterTypes: params.paramTypes,
                        returnType: nestedType,
                        valueParameterSymbols: params.paramSymbols,
                        valueParameterHasDefaultValues: params.paramHasDefaultValues,
                        valueParameterIsVararg: params.paramIsVararg,
                        valueParameterAllowsNonLocalReturn: params.paramAllowsNonLocalReturn,
                        typeParameterSymbols: nestedTypeParamSymbols,
                        classTypeParameterCount: nestedTypeParamSymbols.count
                    ),
                    for: secCtorSymbol
                )
            }

            // Value class validation: must have exactly one primary constructor parameter
            if isValueClassDeclaration(nestedClass) {
                symbols.insertFlags(.valueType, for: nestedSymbol)
                let valParams = nestedClass.primaryConstructorParams
                if valParams.count != 1 {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0070",
                        "Value class must have exactly one primary constructor parameter.",
                        range: nestedClass.range
                    )
                } else {
                    let singleParam = valParams[0]
                    let underlyingType = resolveTypeRef(
                        singleParam.type,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        localTypeParameters: nestedLocalTypeParameters,
                        relativeOwnerFQName: nestedFQName,
                        currentPackageFQName: sourcePackageFQName,
                        imports: sourceImports,
                        diagnostics: diagnostics
                    ) ?? anyType
                    symbols.setValueClassUnderlyingType(underlyingType, for: nestedSymbol)
                }
                if !nestedClass.secondaryConstructors.isEmpty {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0071",
                        "Value class cannot have secondary constructors.",
                        range: nestedClass.range
                    )
                }
            }

            if classSymbolKind(for: nestedClass) == .enumClass {
                for entry in nestedClass.enumEntries {
                    let entryFQName = nestedFQName + [entry.name]
                    checkAndReportDuplicateDeclaration(
                        newKind: .field,
                        fqName: entryFQName,
                        range: entry.range,
                        symbols: symbols,
                        diagnostics: diagnostics
                    )
                    let entrySymbol = symbols.define(
                        kind: .field,
                        name: entry.name,
                        fqName: entryFQName,
                        declSite: entry.range,
                        visibility: .public,
                        flags: []
                    )
                    symbols.setParentSymbol(nestedSymbol, for: entrySymbol)
                    symbols.setPropertyType(nestedType, for: entrySymbol)
                    nestedScope.insert(entrySymbol)
                }
                collectSyntheticEnumEntryProperties(
                    ownerSymbol: nestedSymbol,
                    ownerFQName: nestedFQName,
                    symbols: symbols,
                    types: types,
                    scope: nestedScope,
                    interner: interner
                )
                collectSyntheticEnumValuesMember(
                    ownerSymbol: nestedSymbol,
                    ownerFQName: nestedFQName,
                    enumType: nestedType,
                    symbols: symbols,
                    types: types,
                    scope: nestedScope,
                    interner: interner
                )
            }
            if nestedClass.modifiers.contains(.data) {
                collectSyntheticDataClassMethods(
                    classDecl: nestedClass,
                    ast: ast,
                    ownerSymbol: nestedSymbol,
                    ownerFQName: nestedFQName,
                    ownerType: nestedType,
                    phase: .beforeMemberHeaders,
                    symbols: symbols,
                    types: types,
                    scope: nestedScope,
                    interner: interner,
                    diagnostics: diagnostics,
                    localTypeParameters: nestedLocalTypeParameters
                )
            }
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: nestedClass.memberFunctions,
                    properties: nestedClass.memberProperties,
                    nestedClasses: [],
                    nestedObjects: []
                ),
                owner: OwnerContext(fqName: nestedFQName, symbol: nestedSymbol, type: nestedType),
                sourceFileID: sourceFileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: nestedScope,
                diagnostics: diagnostics,
                interner: interner,
                classTypeParameterSymbols: nestedTypeParamSymbols,
                classLocalTypeParameters: nestedLocalTypeParameters
            )
            if nestedClass.modifiers.contains(.data) {
                collectSyntheticDataClassMethods(
                    classDecl: nestedClass,
                    ast: ast,
                    ownerSymbol: nestedSymbol,
                    ownerFQName: nestedFQName,
                    ownerType: nestedType,
                    phase: .afterMemberHeaders,
                    symbols: symbols,
                    types: types,
                    scope: nestedScope,
                    interner: interner,
                    diagnostics: diagnostics,
                    localTypeParameters: nestedLocalTypeParameters
                )
            }
            if let companionDeclID = nestedClass.companionObject {
                collectCompanionObjectHeader(
                    companionDeclID: companionDeclID,
                    ownerFQName: nestedFQName,
                    ownerSymbol: nestedSymbol,
                    ownerType: nestedType,
                    sourceFileID: sourceFileID,
                    ctx: ctx,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: nestedScope,
                    diagnostics: diagnostics,
                    interner: interner
                )
            } else if nestedClassKind == .enumClass {
                // Synthesize implicit companion for enum classes (valueOf, entries)
                let companionName = interner.intern("Companion")
                let companionFQName = nestedFQName + [companionName]
                let companionSymbol = symbols.define(
                    kind: .object,
                    name: companionName,
                    fqName: companionFQName,
                    declSite: nestedClass.range,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(nestedSymbol, for: companionSymbol)
                symbols.setCompanionObjectSymbol(companionSymbol, for: nestedSymbol)
                nestedScope.insert(companionSymbol)
                let companionType = types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                let companionScope = ClassMemberScope(
                    parent: nestedScope,
                    symbols: symbols,
                    ownerSymbol: companionSymbol,
                    thisType: companionType
                )
                collectSyntheticEnumCompanionMembers(
                    companionSymbol: companionSymbol,
                    companionFQName: companionFQName,
                    enumType: nestedType,
                    symbols: symbols,
                    types: types,
                    scope: companionScope,
                    interner: interner
                )
            }
        case let .interfaceDecl(nestedInterface):
            let nestedFQName = ownerFQName + [nestedInterface.name]
            var nestedFlags = flags(from: nestedInterface.modifiers)
            if nestedInterface.isFunInterface {
                nestedFlags.insert(.funInterface)
            }
            let nestedSymbol = collectNestedDeclarationHeader(
                kind: .interface,
                name: nestedInterface.name,
                fqName: nestedFQName,
                declSite: nestedInterface.range,
                visibility: visibility(from: nestedInterface.modifiers),
                flags: nestedFlags,
                duplicateCheckFlags: flags(from: nestedInterface.modifiers),
                ownerSymbol: ownerSymbol,
                sourceFileID: sourceFileID,
                sourceManager: sourceManager,
                declID: declID,
                decl: decl,
                symbols: symbols,
                diagnostics: diagnostics,
                bindings: bindings,
                scope: scope,
                ast: ast,
                interner: interner
            )

            let nestedType = types.make(.classType(ClassType(classSymbol: nestedSymbol, args: [], nullability: .nonNull)))
            let nestedScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: nestedSymbol,
                thisType: nestedType
            )
            if !nestedInterface.typeParams.isEmpty {
                types.setNominalTypeParameterVariances(
                    nestedInterface.typeParams.map(\.variance),
                    for: nestedSymbol
                )
            }
            collectNestedTypeAliases(
                nestedInterface.nestedTypeAliases,
                ownerFQName: nestedFQName,
                sourceFileID: sourceFileID,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: nestedInterface.memberFunctions,
                    properties: nestedInterface.memberProperties,
                    nestedClasses: nestedInterface.nestedClasses,
                    nestedObjects: nestedInterface.nestedObjects
                ),
                owner: OwnerContext(fqName: nestedFQName, symbol: nestedSymbol, type: nestedType),
                sourceFileID: sourceFileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: nestedScope,
                diagnostics: diagnostics,
                interner: interner
            )
            if let companionDeclID = nestedInterface.companionObject {
                collectCompanionObjectHeader(
                    companionDeclID: companionDeclID,
                    ownerFQName: nestedFQName,
                    ownerSymbol: nestedSymbol,
                    ownerType: nestedType,
                    sourceFileID: sourceFileID,
                    ctx: ctx,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: nestedScope,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        default:
            break
        }
    }

    private func collectNestedObjectHeader(
        declID: DeclID,
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        sourceFileID: FileID,
        ctx: CompilationContext,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let sourceManager = ctx.sourceManager
        guard let decl = ast.arena.decl(declID),
              case let .objectDecl(nestedObject) = decl
        else {
            return
        }
        let nestedFQName = ownerFQName + [nestedObject.name]
        let nestedObjectFlags = flags(from: nestedObject.modifiers)
        let nestedSymbol = collectNestedDeclarationHeader(
            kind: .object,
            name: nestedObject.name,
            fqName: nestedFQName,
            declSite: nestedObject.range,
            visibility: visibility(from: nestedObject.modifiers),
            flags: nestedObjectFlags,
            duplicateCheckFlags: nestedObjectFlags,
            ownerSymbol: ownerSymbol,
            sourceFileID: sourceFileID,
            sourceManager: sourceManager,
            declID: declID,
            decl: decl,
            symbols: symbols,
            diagnostics: diagnostics,
            bindings: bindings,
            scope: scope,
            ast: ast,
            interner: interner
        )

        let nestedType = types.make(.classType(ClassType(classSymbol: nestedSymbol, args: [], nullability: .nonNull)))
        let nestedScope = ClassMemberScope(
            parent: scope,
            symbols: symbols,
            ownerSymbol: nestedSymbol,
            thisType: nestedType
        )
        collectNestedTypeAliases(
            nestedObject.nestedTypeAliases,
            ownerFQName: nestedFQName,
            sourceFileID: sourceFileID,
            ast: ast,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner
        )
        collectMemberHeaders(
            members: MemberDeclarations(
                functions: nestedObject.memberFunctions,
                properties: nestedObject.memberProperties,
                nestedClasses: nestedObject.nestedClasses,
                nestedObjects: nestedObject.nestedObjects
            ),
            owner: OwnerContext(fqName: nestedFQName, symbol: nestedSymbol, type: nestedType),
            sourceFileID: sourceFileID,
            ctx: ctx,
            ast: ast,
            symbols: symbols,
            types: types,
            bindings: bindings,
            scope: nestedScope,
            diagnostics: diagnostics,
            interner: interner
        )
        if nestedObject.modifiers.contains(.data) {
            collectSyntheticToString(
                ownerSymbol: nestedSymbol,
                ownerFQName: nestedFQName,
                ownerType: nestedType,
                requireDataTypeFlag: false,
                symbols: symbols,
                types: types,
                scope: nestedScope,
                interner: interner
            )
            collectSyntheticEquals(
                ownerSymbol: nestedSymbol,
                ownerFQName: nestedFQName,
                ownerType: nestedType,
                requireDataTypeFlag: false,
                symbols: symbols,
                types: types,
                scope: nestedScope,
                interner: interner
            )
        }
    }

    // Collects companion object header: creates the companion symbol, links it to the owner class,
    // and registers companion members under the companion's fully qualified name. Resolution of
    // `ClassName.memberName` to companion members is handled separately by the call/type checker.

    /// Returns a synthetic member function placeholder with the same fully-qualified
    /// name and parent, so bundled source declarations can claim pre-registered
    /// methods instead of creating a duplicate symbol.
    ///
    /// Reuse is restricted to bundled stdlib sources or an explicit owner allow-list
    /// (currently `kotlin.Comparator`) to avoid accidentally overwriting user-declared
    /// symbols. The placeholder's value-parameter count and visibility must also match
    /// the source declaration so the bundled implementation fully replaces the stub.
    private func reusableSyntheticMemberFunctionSymbol(
        fqName: [InternedString],
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        valueParamCount: Int,
        expectedVisibility: Visibility,
        sourceFileID: FileID,
        sourceManager: SourceManager,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let isBundledSource = sourceManager.origin(of: sourceFileID)?.isBundledStdlib == true
        let isAllowedOwner = ownerFQName == [interner.intern("kotlin"), interner.intern("Comparator")]
        guard isBundledSource || isAllowedOwner else {
            return nil
        }

        return symbols.lookupAll(fqName: fqName).first { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  symbol.flags.contains(.synthetic),
                  symbol.visibility == expectedVisibility,
                  symbols.parentSymbol(for: symbolID) == ownerSymbol,
                  let signature = symbols.functionSignature(for: symbolID),
                  signature.parameterTypes.count == valueParamCount
            else {
                return false
            }
            return true
        }
    }

    /// Returns a synthetic property placeholder with the same fully-qualified name
    /// and parent, so bundled source declarations can claim runtime-backed properties.
    private func reusableSyntheticMemberPropertySymbol(
        fqName: [InternedString],
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        expectedVisibility: Visibility,
        sourceFileID: FileID,
        sourceManager: SourceManager,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let isBundledSource = sourceManager.origin(of: sourceFileID)?.isBundledStdlib == true
        let isAllowedOwner = ownerFQName == [interner.intern("kotlin"), interner.intern("Comparator")]
        guard isBundledSource || isAllowedOwner else {
            return nil
        }

        return symbols.lookupAll(fqName: fqName).first { symbolID in
            guard let symbol = symbols.symbol(symbolID) else { return false }
            return symbol.kind == .property
                && symbol.flags.contains(.synthetic)
                && symbol.visibility == expectedVisibility
                && symbols.parentSymbol(for: symbolID) == ownerSymbol
        }
    }

}
