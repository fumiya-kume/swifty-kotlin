import Foundation

extension DataFlowSemaPhase {
    func bindInheritanceEdges(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                bindInheritanceEdges(
                    declID: declID,
                    currentPackage: file.packageFQName,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    types: types,
                    interner: interner
                )
            }
        }
    }

    private func bindInheritanceEdges(
        declID: DeclID,
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let symbol = bindings.declSymbols[declID],
              let decl = ast.arena.decl(declID)
        else {
            return
        }

        let superTypeRefs: [TypeRefID]
        let nestedDecls: [DeclID]
        switch decl {
        case let .classDecl(classDecl):
            superTypeRefs = classDecl.superTypeEntries.map(\.typeRef)
            nestedDecls = classDecl.nestedClasses + classDecl.nestedObjects
                + (classDecl.companionObject.map { [$0] } ?? [])
        case let .interfaceDecl(interfaceDecl):
            superTypeRefs = interfaceDecl.superTypes
            nestedDecls = interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
                + (interfaceDecl.companionObject.map { [$0] } ?? [])
        case let .objectDecl(objectDecl):
            superTypeRefs = objectDecl.superTypes
            nestedDecls = objectDecl.nestedClasses + objectDecl.nestedObjects
        default:
            return
        }

        var superSymbols: [SymbolID] = []
        for superTypeRef in superTypeRefs {
            if let resolved = resolveNominalSymbolAndTypeArgs(
                superTypeRef,
                currentPackage: currentPackage,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                superSymbols.append(resolved.symbol)
                if !resolved.typeArgs.isEmpty {
                    symbols.setSupertypeTypeArgs(resolved.typeArgs, for: symbol, supertype: resolved.symbol)
                    types.setNominalSupertypeTypeArgs(resolved.typeArgs, for: symbol, supertype: resolved.symbol)
                }
            }
        }
        let uniqueSuperSymbols = Array(Set(superSymbols)).sorted(by: { $0.rawValue < $1.rawValue })
        symbols.setDirectSupertypes(uniqueSuperSymbols, for: symbol)
        types.setNominalDirectSupertypes(uniqueSuperSymbols, for: symbol)

        for nestedDeclID in nestedDecls {
            bindInheritanceEdges(
                declID: nestedDeclID,
                currentPackage: currentPackage,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                types: types,
                interner: interner
            )
        }
    }

    private struct ResolvedSupertype {
        let symbol: SymbolID
        let typeArgs: [TypeArg]
    }

    private func resolveNominalSymbolAndTypeArgs(
        _ typeRefID: TypeRefID,
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> ResolvedSupertype? {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }
        let path: [InternedString]
        let argRefs: [TypeArgRef]
        switch typeRef {
        case let .named(refPath, refs, _):
            path = refPath
            argRefs = refs
        case .functionType, .intersection:
            return nil
        }
        guard !path.isEmpty else {
            return nil
        }

        var candidatePaths: [[InternedString]] = [path]
        if path.count == 1, !currentPackage.isEmpty {
            candidatePaths.append(currentPackage + path)
        }

        for candidatePath in candidatePaths {
            if let symbol = symbols.lookupAll(fqName: candidatePath)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id
            {
                let resolvedArgs = resolveTypeArgRefsForInheritance(
                    argRefs,
                    currentPackage: currentPackage,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner
                )
                return ResolvedSupertype(symbol: symbol, typeArgs: resolvedArgs)
            }
        }
        return nil
    }

    private func resolveTypeArgRefsForInheritance(
        _ argRefs: [TypeArgRef],
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [TypeArg] {
        // Use all-or-nothing semantics: if any type arg fails to resolve,
        // return an empty array to preserve positional integrity.
        var result: [TypeArg] = []
        result.reserveCapacity(argRefs.count)
        for argRef in argRefs {
            switch argRef {
            case let .invariant(innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types, interner: interner) else {
                    return []
                }
                result.append(.invariant(resolved))
            case let .out(innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types, interner: interner) else {
                    return []
                }
                result.append(.out(resolved))
            case let .in(innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types, interner: interner) else {
                    return []
                }
                result.append(.in(resolved))
            case .star:
                result.append(.star)
            }
        }
        return result
    }

    private func resolveTypeRefForInheritance(
        _ typeRefID: TypeRefID,
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID? {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }
        switch typeRef {
        case let .named(path, argRefs, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            guard !path.isEmpty else {
                return nil
            }
            // Try both raw path and package-qualified path (same as resolveNominalSymbolAndTypeArgs)
            var candidatePaths: [[InternedString]] = [path]
            if path.count == 1, !currentPackage.isEmpty {
                candidatePaths.append(currentPackage + path)
            }
            for candidatePath in candidatePaths {
                if let nominalSymbol = symbols.lookupAll(fqName: candidatePath)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalTypeSymbol($0.kind) })
                {
                    let resolvedArgs = resolveTypeArgRefsForInheritance(argRefs, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types, interner: interner)
                    return types.make(.classType(ClassType(classSymbol: nominalSymbol.id, args: resolvedArgs, nullability: nullability)))
                }
            }
            // Resolve built-in/primitive type names that don't have symbol table entries
            if path.count == 1 {
                if let builtinType = resolveBuiltinTypeNameForInheritance(
                    path[0],
                    interner: interner,
                    nullability: nullability,
                    types: types
                ) {
                    return builtinType
                }
            }
            return nil
        case let .functionType(paramRefIDs, returnRefID, isSuspend, nullable):
            return resolveFunctionTypeForInheritance(
                paramRefIDs: paramRefIDs, returnRefID: returnRefID, isSuspend: isSuspend, nullable: nullable,
                currentPackage: currentPackage, ast: ast, symbols: symbols, types: types, interner: interner
            )
        case let .intersection(partRefs):
            let partTypes = partRefs.compactMap { resolveTypeRefForInheritance($0, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types, interner: interner) }
            guard partTypes.count == partRefs.count else { return nil }
            return types.make(.intersection(partTypes))
        }
    }

    private func resolveFunctionTypeForInheritance(
        paramRefIDs: [TypeRefID],
        returnRefID: TypeRefID,
        isSuspend: Bool,
        nullable: Bool,
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID? {
        let nullability: Nullability = nullable ? .nullable : .nonNull
        var paramTypes: [TypeID] = []
        for paramRef in paramRefIDs {
            guard let paramType = resolveTypeRefForInheritance(
                paramRef, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types, interner: interner
            ) else { return nil }
            paramTypes.append(paramType)
        }
        guard let returnType = resolveTypeRefForInheritance(
            returnRefID, currentPackage: currentPackage, ast: ast, symbols: symbols, types: types, interner: interner
        ) else { return nil }
        return types.make(.functionType(FunctionType(
            params: paramTypes, returnType: returnType, isSuspend: isSuspend, nullability: nullability
        )))
    }

    private func resolveBuiltinTypeNameForInheritance(
        _ name: InternedString,
        interner: StringInterner,
        nullability: Nullability,
        types: TypeSystem
    ) -> TypeID? {
        if let builtinType = BuiltinTypeNames(interner: interner).resolveBuiltinType(name, nullability: nullability, types: types) {
            return builtinType
        }
        if name == interner.intern("Byte") || name == interner.intern("Short") {
            return types.make(.primitive(.int, nullability))
        }
        return nil
    }

    func isNominalTypeSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            true
        default:
            false
        }
    }

    // P5-112: Validate that concrete subclasses of abstract classes override all abstract members.
    func validateAbstractOverrides(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateAbstractOverridesForDecl(
                    declID: declID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        }
    }

    /// CLASS-008: Validate class delegation (`: Interface by expr`).
    /// Ensures delegated supertypes are interfaces (not classes) and records them for abstract override exemption.
    func validateClassDelegation(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .classDecl(classDecl) = decl
                else {
                    continue
                }
                for entry in classDecl.superTypeEntries where entry.delegateExpression != nil {
                    guard let resolved = resolveNominalSymbolAndTypeArgs(
                        entry.typeRef,
                        currentPackage: file.packageFQName,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner
                    ) else {
                        continue
                    }
                    guard let superSymbol = symbols.symbol(resolved.symbol) else {
                        continue
                    }
                    if superSymbol.kind != .interface {
                        let name = superSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        diagnostics.error(
                            "KSWIFTK-SEMA-DELEGATE",
                            "Class delegation is only supported for interfaces, not '\(name)'.",
                            range: classDecl.range
                        )
                    } else if let classSymbol = bindings.declSymbols[declID],
                              let classSym = symbols.symbol(classSymbol),
                              let delegateExpr = entry.delegateExpression
                    {
                        symbols.addDelegatedInterface(resolved.symbol, forClass: classSymbol)
                        symbols.setClassDelegationExpr(delegateExpr, forClass: classSymbol, interface: resolved.symbol)
                        let interfaceName = interner.resolve(superSymbol.fqName.last ?? interner.intern(""))
                        let fieldName = interner.intern("$delegate_\(interfaceName)")
                        let fieldFQName = classSym.fqName + [fieldName]
                        let fieldSymbol = symbols.define(
                            kind: .field,
                            name: fieldName,
                            fqName: fieldFQName,
                            declSite: classDecl.range,
                            visibility: .private,
                            flags: []
                        )
                        symbols.setParentSymbol(classSymbol, for: fieldSymbol)
                        let interfaceType = types.make(.classType(ClassType(
                            classSymbol: resolved.symbol,
                            args: resolved.typeArgs,
                            nullability: .nonNull
                        )))
                        symbols.setPropertyType(interfaceType, for: fieldSymbol)
                        symbols.setClassDelegationField(fieldSymbol, forClass: classSymbol, interface: resolved.symbol)
                    }
                }
            }
        }
    }

    /// CLASS-008: Create synthetic method symbols for delegated interface methods
    /// that the class does not override. These are used for itable layout and KIR lowering.
    private struct DelegationDispatchKey: Hashable {
        let name: InternedString
        let arity: Int
        let isSuspend: Bool
    }

    private func delegationDispatchKey(for methodSymbol: SymbolID, symbols: SymbolTable, interner: StringInterner) -> DelegationDispatchKey {
        let signature = symbols.functionSignature(for: methodSymbol)
        let methodInfo = symbols.symbol(methodSymbol)
        return DelegationDispatchKey(
            name: methodInfo?.name ?? interner.intern(""),
            arity: signature?.parameterTypes.count ?? 0,
            isSuspend: signature?.isSuspend ?? false
        )
    }

    func synthesizeClassDelegationForwardingMethodSymbols(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .classDecl(classDecl) = decl,
                      let classSymbol = bindings.declSymbols[declID],
                      let classSym = symbols.symbol(classSymbol)
                else {
                    continue
                }
                synthesizeDelegationForwardingForClass(
                    classDecl: classDecl, classSymbol: classSymbol, classFQName: classSym.fqName,
                    symbols: symbols, bindings: bindings, types: types, interner: interner
                )
            }
        }
    }

    private func synthesizeDelegationForwardingForClass(
        classDecl: ClassDecl,
        classSymbol: SymbolID,
        classFQName: [InternedString],
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        var classMethodKeys: Set<DelegationDispatchKey> = []
        for funDeclID in classDecl.memberFunctions {
            guard let funSymbol = bindings.declSymbols[funDeclID] else { continue }
            classMethodKeys.insert(delegationDispatchKey(for: funSymbol, symbols: symbols, interner: interner))
        }

        for interfaceSymbol in symbols.delegatedInterfaces(forClass: classSymbol) {
            guard let fieldSymbol = symbols.classDelegationField(forClass: classSymbol, interface: interfaceSymbol),
                  let interfaceSym = symbols.symbol(interfaceSymbol)
            else {
                continue
            }
            let interfaceMethods = symbols.children(ofFQName: interfaceSym.fqName)
                .compactMap { symbols.symbol($0) }
                .filter { $0.kind == .function }

            for methodSym in interfaceMethods {
                let key = delegationDispatchKey(for: methodSym.id, symbols: symbols, interner: interner)
                guard !classMethodKeys.contains(key),
                      let ifaceSig = symbols.functionSignature(for: methodSym.id)
                else { continue }
                synthesizeForwardingMethod(
                    methodSym: methodSym, ifaceSig: ifaceSig,
                    classDecl: classDecl, classSymbol: classSymbol, classFQName: classFQName,
                    interfaceSymbol: interfaceSymbol, fieldSymbol: fieldSymbol,
                    symbols: symbols, types: types, interner: interner
                )
            }
        }
    }

    private func synthesizeForwardingMethod(
        methodSym: SemanticSymbol,
        ifaceSig: FunctionSignature,
        classDecl: ClassDecl,
        classSymbol: SymbolID,
        classFQName: [InternedString],
        interfaceSymbol: SymbolID,
        fieldSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let methodName = methodSym.name
        let forwardingFQName = classFQName + [methodName]
        let forwardingSymbol = symbols.define(
            kind: .function,
            name: methodName,
            fqName: forwardingFQName,
            declSite: classDecl.range,
            visibility: methodSym.visibility,
            flags: [.synthetic, .overrideMember]
        )
        symbols.setParentSymbol(classSymbol, for: forwardingSymbol)

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol, args: [], nullability: .nonNull
        )))

        var paramSymbols: [SymbolID] = []
        for (index, paramType) in ifaceSig.parameterTypes.enumerated() {
            let paramName = interner.intern("p\(index)")
            let paramFQName = forwardingFQName + [paramName]
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: paramFQName,
                declSite: classDecl.range,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(forwardingSymbol, for: paramSymbol)
            symbols.setPropertyType(paramType, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        let forwardingSig = FunctionSignature(
            receiverType: classType,
            parameterTypes: ifaceSig.parameterTypes,
            returnType: ifaceSig.returnType,
            isSuspend: ifaceSig.isSuspend,
            valueParameterSymbols: paramSymbols,
            valueParameterHasDefaultValues: Array(repeating: false, count: paramSymbols.count),
            valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)
        )
        symbols.setFunctionSignature(forwardingSig, for: forwardingSymbol)

        symbols.addClassDelegationForwardingMethod(
            forwardingSymbol,
            forClass: classSymbol,
            interface: interfaceSymbol,
            interfaceMethod: methodSym.id,
            field: fieldSymbol
        )
    }

    private func validateAbstractOverridesForDecl(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let symbol = bindings.declSymbols[declID],
              let decl = ast.arena.decl(declID),
              let symbolInfo = symbols.symbol(symbol)
        else {
            return
        }

        // Recursively validate nested classes
        switch decl {
        case let .classDecl(classDecl):
            for nestedDeclID in classDecl.nestedClasses {
                validateAbstractOverridesForDecl(
                    declID: nestedDeclID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        case let .interfaceDecl(interfaceDecl):
            for nestedDeclID in interfaceDecl.nestedClasses {
                validateAbstractOverridesForDecl(
                    declID: nestedDeclID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        case let .objectDecl(objectDecl):
            for nestedDeclID in objectDecl.nestedClasses {
                validateAbstractOverridesForDecl(
                    declID: nestedDeclID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        default:
            return
        }

        // Only check concrete class/object declarations (not abstract, not interface)
        guard symbolInfo.kind == .class || symbolInfo.kind == .object,
              !symbolInfo.flags.contains(.abstractType)
        else {
            return
        }

        // Collect all abstract members from the entire supertype chain
        let abstractMembers = collectInheritedAbstractMembers(
            for: symbol,
            symbols: symbols
        )
        guard !abstractMembers.isEmpty else { return }

        // CLASS-008: Abstract members from delegated interfaces are satisfied by delegation.
        let delegatedInterfaces = symbols.delegatedInterfaces(forClass: symbol)

        // Collect the names of members that this class provides overrides for
        let overriddenNames = collectOverriddenMemberNames(
            for: symbol,
            decl: decl,
            ast: ast,
            symbols: symbols
        )

        // Check that every abstract member name is overridden (or delegated)
        for abstractMember in abstractMembers {
            guard let abstractSym = symbols.symbol(abstractMember) else { continue }
            // Skip if this abstract member belongs to a delegated interface
            if let owner = symbols.parentSymbol(for: abstractMember),
               delegatedInterfaces.contains(owner)
            {
                continue
            }
            let memberName = interner.resolve(abstractSym.name)
            if !overriddenNames.contains(abstractSym.name) {
                let className = symbolInfo.fqName.map { interner.resolve($0) }.joined(separator: ".")
                let declRange: SourceRange? = switch decl {
                case let .classDecl(cd): cd.range
                case let .objectDecl(od): od.range
                default: nil
                }
                diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Class '\(className)' must override abstract member '\(memberName)' or be declared abstract.",
                    range: declRange
                )
            }
        }
    }

    /// Collects all abstract member symbol IDs from the entire supertype chain of a class,
    /// filtering out those that have been concretely overridden by intermediate classes.
    private func collectInheritedAbstractMembers(
        for classSymbol: SymbolID,
        symbols: SymbolTable
    ) -> [SymbolID] {
        var abstractMembersByName: [InternedString: SymbolID] = [:]
        var concreteOverrideNames: Set<InternedString> = []
        var visited: Set<SymbolID> = [classSymbol]
        var queue = symbols.directSupertypes(for: classSymbol)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            guard let currentSym = symbols.symbol(current) else { continue }

            let children = symbols.children(ofFQName: currentSym.fqName)
            for childID in children {
                guard let childSym = symbols.symbol(childID) else { continue }
                if childSym.kind == .function || childSym.kind == .property {
                    if childSym.flags.contains(.abstractType) {
                        // Only record the abstract member if we haven't seen
                        // a concrete override for this name yet.
                        if !concreteOverrideNames.contains(childSym.name) {
                            abstractMembersByName[childSym.name] = childID
                        }
                    } else {
                        // This is a concrete member. Only treat it as satisfying
                        // abstract requirements from higher supertypes if no closer
                        // supertype has already (re-)abstracted this name.
                        if abstractMembersByName[childSym.name] == nil {
                            concreteOverrideNames.insert(childSym.name)
                        }
                    }
                }
            }

            // Continue walking supertypes
            queue.append(contentsOf: symbols.directSupertypes(for: current))
        }

        return Array(abstractMembersByName.values)
    }

    /// Collects the set of member names that this class provides via `override`.
    func collectOverriddenMemberNames(
        for _: SymbolID,
        decl: Decl,
        ast: ASTModule,
        symbols _: SymbolTable
    ) -> Set<InternedString> {
        var overriddenNames: Set<InternedString> = []

        let memberFunctions: [DeclID]
        let memberProperties: [DeclID]
        switch decl {
        case let .classDecl(classDecl):
            memberFunctions = classDecl.memberFunctions
            memberProperties = classDecl.memberProperties
        case let .objectDecl(objectDecl):
            memberFunctions = objectDecl.memberFunctions
            memberProperties = objectDecl.memberProperties
        default:
            return overriddenNames
        }

        for memberDeclID in memberFunctions {
            guard let memberDecl = ast.arena.decl(memberDeclID),
                  case let .funDecl(funDecl) = memberDecl else { continue }
            if funDecl.modifiers.contains(.override) {
                overriddenNames.insert(funDecl.name)
            }
        }

        for memberDeclID in memberProperties {
            guard let memberDecl = ast.arena.decl(memberDeclID),
                  case let .propertyDecl(propertyDecl) = memberDecl else { continue }
            if propertyDecl.modifiers.contains(.override) {
                overriddenNames.insert(propertyDecl.name)
            }
        }

        return overriddenNames
    }

    // P5-78: Validate that direct subclasses of sealed types are in the same package.
    func validateSealedHierarchy(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = bindings.declSymbols[declID],
                      let decl = ast.arena.decl(declID),
                      let symbolInfo = symbols.symbol(symbol)
                else {
                    continue
                }
                // Only check class and interface declarations that have supertypes
                let hasSuperTypes: Bool
                switch decl {
                case let .classDecl(classDecl):
                    hasSuperTypes = !classDecl.superTypeEntries.isEmpty
                case let .interfaceDecl(interfaceDecl):
                    hasSuperTypes = !interfaceDecl.superTypes.isEmpty
                case let .objectDecl(objectDecl):
                    hasSuperTypes = !objectDecl.superTypes.isEmpty
                default:
                    continue
                }
                guard hasSuperTypes else { continue }

                let supertypes = symbols.directSupertypes(for: symbol)
                for supertypeID in supertypes {
                    guard let supertypeSymbol = symbols.symbol(supertypeID),
                          supertypeSymbol.flags.contains(.sealedType)
                    else {
                        continue
                    }
                    // Check same-package: compare package prefixes
                    let subtypePackage = Array(symbolInfo.fqName.dropLast())
                    let supertypePackage = Array(supertypeSymbol.fqName.dropLast())
                    if subtypePackage != supertypePackage {
                        let subtypeName = symbolInfo.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        let supertypeName = supertypeSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        diagnostics.error(
                            "KSWIFTK-SEMA-0070",
                            "'\(subtypeName)' cannot inherit from sealed type '\(supertypeName)': sealed subclasses must be in the same package.",
                            range: ast.arena.decl(declID).flatMap { d -> SourceRange? in
                                switch d {
                                case let .classDecl(cd): return cd.range
                                case let .interfaceDecl(id): return id.range
                                case let .objectDecl(od): return od.range
                                default: return nil
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}
