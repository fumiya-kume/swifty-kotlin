import Foundation

extension ExprTypeChecker {
    func inferObjectLiteralExpr(
        _ id: ExprID,
        superTypes: [TypeRefID],
        declID: DeclID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        guard let declID,
              let decl = ast.arena.decl(declID),
              case let .objectDecl(objectDecl) = decl
        else {
            let objectType = superTypes.first.map {
                driver.helpers.resolveTypeRef(
                    $0,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            } ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: objectType)
            return objectType
        }

        let objectSymbol = ensureObjectLiteralSymbol(
            declID: declID,
            objectDecl: objectDecl,
            superTypes: superTypes,
            ctx: ctx,
            locals: &locals
        )
        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        sema.bindings.bindExprType(id, type: objectType)
        return objectType
    }

    private func ensureObjectLiteralSymbol(
        declID: DeclID,
        objectDecl: ObjectDecl,
        superTypes: [TypeRefID],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> SymbolID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        if let existing = sema.bindings.declSymbols[declID] {
            return existing
        }

        let objectSymbol = sema.symbols.define(
            kind: .class,
            name: objectDecl.name,
            fqName: [objectDecl.name],
            declSite: objectDecl.range,
            visibility: .public,
            flags: [.synthetic]
        )
        sema.bindings.bindDecl(declID, symbol: objectSymbol)
        sema.symbols.setSourceFileID(ctx.currentFileID, for: objectSymbol)

        var directSuperSymbols: [SymbolID] = []
        directSuperSymbols.reserveCapacity(superTypes.count)
        for superTypeRef in superTypes {
            let resolved = driver.helpers.resolveTypeRef(
                superTypeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                diagnostics: ctx.semaCtx.diagnostics
            )
            if case let .classType(classType) = sema.types.kind(of: resolved),
               !directSuperSymbols.contains(classType.classSymbol)
            {
                directSuperSymbols.append(classType.classSymbol)
            }
        }
        sema.symbols.setDirectSupertypes(directSuperSymbols, for: objectSymbol)

        var propertySymbolsByDecl: [DeclID: SymbolID] = [:]
        for propertyDeclID in objectDecl.memberProperties {
            guard let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            var propertyFlags: SymbolFlags = [.synthetic]
            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }
            let propertySymbol = sema.symbols.define(
                kind: .property,
                name: propertyDecl.name,
                fqName: [objectDecl.name, propertyDecl.name],
                declSite: propertyDecl.range,
                visibility: .public,
                flags: propertyFlags
            )
            sema.bindings.bindDecl(propertyDeclID, symbol: propertySymbol)
            sema.bindings.markObjectLiteralPropertySymbol(propertySymbol)
            sema.symbols.setParentSymbol(objectSymbol, for: propertySymbol)
            sema.symbols.setSourceFileID(ctx.currentFileID, for: propertySymbol)

            let declaredType = propertyDecl.type.map {
                driver.helpers.resolveTypeRef(
                    $0,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            } ?? sema.types.anyType
            sema.symbols.setPropertyType(declaredType, for: propertySymbol)
            propertySymbolsByDecl[propertyDeclID] = propertySymbol
        }

        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        var objectCtx = ctx.with(implicitReceiverType: objectType)
        objectCtx = objectCtx.with(enclosingClassSymbol: objectSymbol)

        for propertyDeclID in objectDecl.memberProperties {
            guard let propertySymbol = propertySymbolsByDecl[propertyDeclID],
                  let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }

            let declaredType = propertyDecl.type.map {
                driver.helpers.resolveTypeRef(
                    $0,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }

            let inferredType: TypeID?
            if let initializer = propertyDecl.initializer {
                let type = driver.inferExpr(
                    initializer,
                    ctx: objectCtx,
                    locals: &locals,
                    expectedType: declaredType
                )
                if let declaredType {
                    driver.emitSubtypeConstraint(
                        left: type,
                        right: declaredType,
                        range: propertyDecl.range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                }
                inferredType = type
            } else {
                inferredType = nil
            }

            sema.symbols.setPropertyType(
                declaredType ?? inferredType ?? sema.types.anyType,
                for: propertySymbol
            )
        }

        let superClass = directSuperSymbols.first(where: { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return false
            }
            return symbol.kind != .interface
        })
        let inheritedLayout = superClass.flatMap { sema.symbols.nominalLayout(for: $0) }
        var fieldOffsets = inheritedLayout?.fieldOffsets ?? [:]
        let objectHeaderWords = inheritedLayout?.objectHeaderWords ?? 2
        var nextFieldOffset = (fieldOffsets.values.max() ?? (objectHeaderWords - 1)) + 1
        for propertyDeclID in objectDecl.memberProperties {
            guard let propertySymbol = propertySymbolsByDecl[propertyDeclID],
                  fieldOffsets[propertySymbol] == nil
            else {
                continue
            }
            fieldOffsets[propertySymbol] = nextFieldOffset
            nextFieldOffset += 1
        }

        let inheritedFieldCount = inheritedLayout?.instanceFieldCount ?? 0
        let instanceFieldCount = inheritedFieldCount + propertySymbolsByDecl.count
        let inheritedInstanceSizeWords = inheritedLayout?.instanceSizeWords ?? 0
        let instanceSizeWords = max(objectHeaderWords + instanceFieldCount, inheritedInstanceSizeWords)
        let inheritedVtableSlots = inheritedLayout?.vtableSlots ?? [:]
        let inheritedItableSlots = inheritedLayout?.itableSlots ?? [:]
        let inheritedVtableSize = inheritedLayout?.vtableSize
        let inheritedItableSize = inheritedLayout?.itableSize

        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: objectHeaderWords,
                instanceFieldCount: instanceFieldCount,
                instanceSizeWords: instanceSizeWords,
                fieldOffsets: fieldOffsets,
                vtableSlots: inheritedVtableSlots,
                itableSlots: inheritedItableSlots,
                vtableSize: inheritedVtableSize,
                itableSize: inheritedItableSize,
                superClass: superClass
            ),
            for: objectSymbol
        )
        return objectSymbol
    }
}
