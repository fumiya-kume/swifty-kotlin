// MARK: - Builder DSL Helpers (STDLIB-002)

/// Extracted from CallTypeChecker to keep file length within SwiftLint limits.
extension CallTypeChecker {
    func builderDSLKind(for name: String) -> BuilderDSLKind? {
        switch name {
        case "buildString":
            .buildString
        case "buildList":
            .buildList
        case "buildMap":
            .buildMap
        default:
            nil
        }
    }

    func shouldUseBuilderDSLSpecialHandling(
        calleeName: InternedString,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        if locals[calleeName] != nil {
            return false
        }
        // Use builder DSL handling when no user-defined (non-synthetic) symbol is in scope.
        // Synthetic stubs (e.g. kotlin.collections.buildList) are allowed.
        if ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            return !sym.flags.contains(.synthetic)
        }) {
            return false
        }
        return true
    }

    func isValidBuilderLambdaArgument(_ argumentExprID: ExprID, ast: ASTModule) -> Bool {
        guard let argumentExpr = ast.arena.expr(argumentExprID),
              case let .lambdaLiteral(params, _, _, _) = argumentExpr
        else {
            return false
        }
        return params.isEmpty
    }

    func builderDSLReceiverType(
        kind: BuilderDSLKind,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        switch kind {
        case .buildString:
            return ensureSyntheticStringBuilderType(sema: sema, interner: interner)
        case .buildList:
            let mutableListFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableList"),
            ]
            guard let mutableListSymbol = sema.symbols.lookup(fqName: mutableListFQName) else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: mutableListSymbol,
                args: [.invariant(sema.types.anyType)],
                nullability: .nonNull
            )))
        case .buildMap:
            let mutableMapFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableMap"),
            ]
            guard let mutableMapSymbol = sema.symbols.lookup(fqName: mutableMapFQName) else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: mutableMapSymbol,
                args: [.invariant(sema.types.anyType), .invariant(sema.types.anyType)],
                nullability: .nonNull
            )))
        }
    }

    /// Returns `Map<K, V>` for `buildMap` where K, V are extracted from `MutableMap<K, V>` receiver type.
    func builderDSLBuildMapReturnType(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let mutableMapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableMap"),
        ]
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]
        guard let mutableMapSymbol = sema.symbols.lookup(fqName: mutableMapFQName),
              let mapSymbol = sema.symbols.lookup(fqName: mapFQName)
        else {
            return sema.types.anyType
        }
        let (keyType, valueType): (TypeID, TypeID) = if case let .classType(ct) = sema.types.kind(of: receiverType),
                                                        ct.classSymbol == mutableMapSymbol,
                                                        ct.args.count >= 2,
                                                        case let .invariant(k) = ct.args[0],
                                                        case let .invariant(v) = ct.args[1]
        {
            (k, v)
        } else {
            (sema.types.anyType, sema.types.anyType)
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
    }

    /// Returns `List<E>` for `buildList` where E is extracted from `MutableList<E>` receiver type.
    func builderDSLBuildListReturnType(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let mutableListFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableList"),
        ]
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let mutableListSymbol = sema.symbols.lookup(fqName: mutableListFQName),
              let listSymbol = sema.symbols.lookup(fqName: listFQName)
        else {
            return sema.types.anyType
        }
        let elementType: TypeID = if case let .classType(ct) = sema.types.kind(of: receiverType),
                                     ct.classSymbol == mutableListSymbol,
                                     let firstArg = ct.args.first,
                                     case let .invariant(elemType) = firstArg
        {
            elemType
        } else {
            sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func ensureSyntheticStringBuilderType(
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let symbols = sema.symbols
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let kotlinTextPkg: [InternedString] = kotlinPkg + [interner.intern("text")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        _ = ensureSyntheticPackage(fqName: kotlinTextPkg, symbols: symbols)

        let stringBuilderName = interner.intern("StringBuilder")
        let stringBuilderFQName = kotlinTextPkg + [stringBuilderName]
        let stringBuilderSymbol: SymbolID = if let existing = symbols.lookup(fqName: stringBuilderFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: stringBuilderName,
                fqName: stringBuilderFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: stringBuilderSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func ensureSyntheticPackage(
        fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID {
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        guard let name = fqName.last else {
            return .invalid
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }
}
