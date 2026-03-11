// MARK: - Builder DSL Helpers (STDLIB-002)

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
        if !ctx.cachedScopeLookup(calleeName).isEmpty {
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
            // Keep current compatibility for map builders.
            return sema.types.anyType
        }
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
