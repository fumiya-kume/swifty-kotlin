import Foundation

extension TypeCheckSemaPassPhase {
    func makeNonNullable(_ type: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: type) {
        case .any(.nullable):
            return types.anyType

        case .primitive(let primitive, .nullable):
            return types.make(.primitive(primitive, .nonNull))

        case .classType(let classType):
            guard classType.nullability == .nullable else {
                return type
            }
            return types.make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: classType.args,
                nullability: .nonNull
            )))

        case .typeParam(let typeParam):
            guard typeParam.nullability == .nullable else {
                return type
            }
            return types.make(.typeParam(TypeParamType(
                symbol: typeParam.symbol,
                nullability: .nonNull
            )))

        case .functionType(let functionType):
            guard functionType.nullability == .nullable else {
                return type
            }
            return types.make(.functionType(FunctionType(
                receiver: functionType.receiver,
                params: functionType.params,
                returnType: functionType.returnType,
                isSuspend: functionType.isSuspend,
                nullability: .nonNull
            )))

        default:
            return type
        }
    }

    func isStableLocalSymbol(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return false
        }
        switch symbol.kind {
        case .valueParameter, .local:
            return !symbol.flags.contains(.mutable)
        default:
            return false
        }
    }

    func arrayElementType(
        for arrayType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard case .classType(let classType) = sema.types.kind(of: arrayType),
              let symbol = sema.symbols.symbol(classType.classSymbol) else {
            return nil
        }
        switch interner.resolve(symbol.name) {
        case "IntArray":
            return sema.types.make(.primitive(.int, .nonNull))
        default:
            return nil
        }
    }

    func kxMiniCoroutineBuiltinReturnType(
        calleeName: InternedString?,
        argumentCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let calleeName else {
            return nil
        }
        switch interner.resolve(calleeName) {
        case "runBlocking":
            guard argumentCount >= 1 else { return nil }
            return sema.types.nullableAnyType
        case "launch":
            guard argumentCount >= 1 else { return nil }
            return sema.types.unitType
        case "async":
            guard argumentCount >= 1 else { return nil }
            return sema.types.nullableAnyType
        case "delay":
            guard argumentCount == 1 else { return nil }
            return sema.types.nullableAnyType
        case "kk_array_new", "IntArray":
            guard argumentCount == 1 else { return nil }
            return sema.types.anyType
        case "kk_array_get":
            guard argumentCount == 2 else { return nil }
            return sema.types.anyType
        case "kk_array_set":
            guard argumentCount == 3 else { return nil }
            return sema.types.unitType
        default:
            return nil
        }
    }

    func binaryOperatorFunctionName(for op: BinaryOp, interner: StringInterner) -> InternedString {
        switch op {
        case .add:
            return interner.intern("plus")
        case .subtract:
            return interner.intern("minus")
        case .multiply:
            return interner.intern("times")
        case .divide:
            return interner.intern("div")
        case .modulo:
            return interner.intern("rem")
        case .equal:
            return interner.intern("equals")
        case .notEqual:
            return interner.intern("equals")
        case .lessThan:
            return interner.intern("compareTo")
        case .lessOrEqual:
            return interner.intern("compareTo")
        case .greaterThan:
            return interner.intern("compareTo")
        case .greaterOrEqual:
            return interner.intern("compareTo")
        case .logicalAnd:
            return interner.intern("and")
        case .logicalOr:
            return interner.intern("or")
        case .elvis:
            return interner.intern("elvis")
        case .rangeTo:
            return interner.intern("rangeTo")
        case .rangeUntil:
            return interner.intern("rangeUntil")
        }
    }

    func resolveTypeRef(
        _ typeRefID: TypeRefID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return sema.types.errorType
        }
        switch typeRef {
        case .named(let path, let argRefs, let nullable):
            guard let firstName = path.first else {
                return sema.types.errorType
            }
            let name = interner.resolve(firstName)
            let nullability: Nullability = nullable ? .nullable : .nonNull
            switch name {
            case "Int":
                return sema.types.make(.primitive(.int, nullability))
            case "Long":
                return sema.types.make(.primitive(.long, nullability))
            case "Float":
                return sema.types.make(.primitive(.float, nullability))
            case "Double":
                return sema.types.make(.primitive(.double, nullability))
            case "Boolean":
                return sema.types.make(.primitive(.boolean, nullability))
            case "Char":
                return sema.types.make(.primitive(.char, nullability))
            case "String":
                return sema.types.make(.primitive(.string, nullability))
            case "Any":
                return nullable ? sema.types.nullableAnyType : sema.types.anyType
            case "Unit":
                return sema.types.unitType
            case "Nothing":
                return sema.types.nothingType
            default:
                let candidates = sema.symbols.lookupAll(fqName: [firstName]).filter { symbolID in
                    guard let sym = sema.symbols.symbol(symbolID) else { return false }
                    switch sym.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        return true
                    default:
                        return false
                    }
                }
                if let symbolID = candidates.first {
                    let resolvedArgs = resolveTypeArgRefsForTypeCheck(
                        argRefs, ast: ast, sema: sema, interner: interner,
                        diagnostics: diagnostics
                    )
                    return sema.types.make(.classType(ClassType(
                        classSymbol: symbolID,
                        args: resolvedArgs,
                        nullability: nullability
                    )))
                }
                diagnostics?.error(
                    "KSWIFTK-SEMA-0025",
                    "Unresolved type '\(name)'.",
                    range: nil
                )
                return sema.types.errorType
            }

        case .functionType(let paramRefIDs, let returnRefID, let isSuspend, let nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            let paramTypes = paramRefIDs.map { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics) }
            let returnType = resolveTypeRef(returnRefID, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics)
            return sema.types.make(.functionType(FunctionType(
                params: paramTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: nullability
            )))
        }
    }

    func resolveTypeArgRefsForTypeCheck(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeArg] {
        argRefs.map { argRef in
            switch argRef {
            case .invariant(let innerRef):
                return .invariant(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics))
            case .out(let innerRef):
                return .out(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics))
            case .in(let innerRef):
                return .in(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics))
            case .star:
                return .star
            }
        }
    }

    func makeNullable(_ type: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: type) {
        case .any(.nonNull):
            return types.nullableAnyType
        case .any(.nullable):
            return type
        case .primitive(let primitive, .nonNull):
            return types.make(.primitive(primitive, .nullable))
        case .primitive(_, .nullable):
            return type
        case .classType(let classType):
            guard classType.nullability == .nonNull else { return type }
            return types.make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: classType.args,
                nullability: .nullable
            )))
        case .typeParam(let typeParam):
            guard typeParam.nullability == .nonNull else { return type }
            return types.make(.typeParam(TypeParamType(
                symbol: typeParam.symbol,
                nullability: .nullable
            )))
        case .functionType(let functionType):
            guard functionType.nullability == .nonNull else { return type }
            return types.make(.functionType(FunctionType(
                receiver: functionType.receiver,
                params: functionType.params,
                returnType: functionType.returnType,
                isSuspend: functionType.isSuspend,
                nullability: .nullable
            )))
        default:
            return type
        }
    }

    func resolveExplicitTypeArgs(
        _ typeArgRefs: [TypeRefID],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeID] {
        guard !typeArgRefs.isEmpty else { return [] }
        return typeArgRefs.map { typeRefID in
            resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics)
        }
    }

    func compoundAssignToBinaryOp(_ op: CompoundAssignOp) -> BinaryOp {
        switch op {
        case .plusAssign: return .add
        case .minusAssign: return .subtract
        case .timesAssign: return .multiply
        case .divAssign: return .divide
        case .modAssign: return .modulo
        }
    }

    func smartCastTypeForWhenSubjectCase(
        conditionID: ExprID,
        subjectType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return nil
        }
        switch conditionExpr {
        case .boolLiteral:
            switch sema.types.kind(of: subjectType) {
            case .primitive(.boolean, _):
                return sema.types.make(.primitive(.boolean, .nonNull))
            default:
                return nil
            }

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                return nil
            }
            guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID],
                  let conditionSymbol = sema.symbols.symbol(conditionSymbolID) else {
                return nil
            }
            switch conditionSymbol.kind {
            case .field:
                guard let enumOwner = enumOwnerSymbol(for: conditionSymbol, symbols: sema.symbols),
                      nominalSymbol(of: subjectType, types: sema.types) == enumOwner else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: enumOwner,
                    args: [],
                    nullability: .nonNull
                )))

            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                guard let subjectNominal = nominalSymbol(of: subjectType, types: sema.types),
                      isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols) else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: conditionSymbolID,
                    args: [],
                    nullability: .nonNull
                )))

            default:
                return nil
            }

        default:
            return nil
        }
    }

    func nominalSymbol(of type: TypeID, types: TypeSystem) -> SymbolID? {
        if case .classType(let classType) = types.kind(of: type) {
            return classType.classSymbol
        }
        return nil
    }

    func collectMemberFunctionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        allowedOwnerSymbols: Set<SymbolID>? = nil
    ) -> [SymbolID] {
        guard let receiverNominal = nominalSymbol(of: receiverType, types: sema.types) else {
            return []
        }

        var ownerQueue: [SymbolID] = [receiverNominal]
        var visitedOwners: Set<SymbolID> = []
        var ownersInLookupOrder: [SymbolID] = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visitedOwners.insert(owner).inserted else {
                continue
            }
            if let allowedOwnerSymbols {
                if allowedOwnerSymbols.contains(owner) {
                    ownersInLookupOrder.append(owner)
                }
            } else {
                ownersInLookupOrder.append(owner)
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }

        if ownersInLookupOrder.isEmpty {
            return []
        }

        var candidates: [SymbolID] = []
        var seenCandidates: Set<SymbolID> = []
        for owner in ownersInLookupOrder {
            guard let ownerSymbol = sema.symbols.symbol(owner) else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard seenCandidates.insert(candidate).inserted,
                      let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.receiverType != nil else {
                    continue
                }
                candidates.append(candidate)
            }
        }
        return candidates
    }

    func enumOwnerSymbol(for entrySymbol: SemanticSymbol, symbols: SymbolTable) -> SymbolID? {
        guard entrySymbol.kind == .field,
              entrySymbol.fqName.count >= 2 else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }

    func isNominalSubtype(
        _ candidate: SymbolID,
        of base: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        if candidate == base {
            return true
        }
        var queue = symbols.directSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next == base {
                return true
            }
            if visited.insert(next).inserted {
                queue.append(contentsOf: symbols.directSupertypes(for: next))
            }
        }
        return false
    }

    func callableTargetForCalleeExpr(
        _ calleeExprID: ExprID,
        sema: SemaModule
    ) -> CallableTarget? {
        if let explicitTarget = sema.bindings.callableTarget(for: calleeExprID) {
            return explicitTarget
        }
        guard let symbol = sema.bindings.identifierSymbol(for: calleeExprID) else {
            return nil
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol) else {
            return .localValue(symbol)
        }
        if semanticSymbol.kind == .function || semanticSymbol.kind == .constructor {
            return .symbol(symbol)
        }
        return .localValue(symbol)
    }

    func callableFunctionType(
        for signature: FunctionSignature,
        bindReceiver: Bool,
        sema: SemaModule
    ) -> TypeID {
        var params = signature.parameterTypes
        if !bindReceiver, let receiverType = signature.receiverType {
            params.insert(receiverType, at: 0)
        }
        return sema.types.make(.functionType(FunctionType(
            params: params,
            returnType: signature.returnType,
            isSuspend: signature.isSuspend,
            nullability: .nonNull
        )))
    }

    func chooseCallableReferenceTarget(
        from candidates: [SymbolID],
        expectedType: TypeID?,
        bindReceiver: Bool,
        sema: SemaModule
    ) -> SymbolID? {
        let sorted = candidates.sorted(by: { $0.rawValue < $1.rawValue })
        guard !sorted.isEmpty else {
            return nil
        }
        guard let expectedType else {
            return sorted.first
        }
        guard case .functionType = sema.types.kind(of: expectedType) else {
            return sorted.first
        }
        if let matched = sorted.first(where: { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            let inferredType = callableFunctionType(
                for: signature,
                bindReceiver: bindReceiver,
                sema: sema
            )
            return sema.types.isSubtype(inferredType, expectedType)
        }) {
            return matched
        }
        return sorted.first
    }

    func collectCapturedOuterSymbols(
        in exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        outerSymbols: Set<SymbolID>,
        skipNestedClosures: Bool = true
    ) -> [SymbolID] {
        guard !outerSymbols.isEmpty else {
            return []
        }

        var captured: Set<SymbolID> = []

        func recordCapture(for targetExprID: ExprID) {
            guard let symbol = sema.bindings.identifierSymbol(for: targetExprID),
                  outerSymbols.contains(symbol) else {
                return
            }
            captured.insert(symbol)
        }

        func visitBody(_ body: FunctionBody) {
            switch body {
            case .block(let exprs, _):
                for expr in exprs {
                    visit(expr)
                }
            case .expr(let expr, _):
                visit(expr)
            case .unit:
                break
            }
        }

        func visit(_ currentExprID: ExprID) {
            guard let expr = ast.arena.expr(currentExprID) else {
                return
            }
            switch expr {
            case .nameRef:
                recordCapture(for: currentExprID)

            case .forExpr(_, let iterable, let body, _):
                visit(iterable)
                visit(body)

            case .whileExpr(let condition, let body, _):
                visit(condition)
                visit(body)

            case .doWhileExpr(let body, let condition, _):
                visit(body)
                visit(condition)

            case .localDecl(_, _, _, let initializer, _):
                if let initializer {
                    visit(initializer)
                }

            case .localAssign(_, let value, _):
                visit(value)

            case .arrayAssign(let array, let index, let value, _):
                visit(array)
                visit(index)
                visit(value)

            case .call(let callee, _, let args, _):
                visit(callee)
                for arg in args {
                    visit(arg.expr)
                }

            case .memberCall(let receiver, _, _, let args, _):
                visit(receiver)
                for arg in args {
                    visit(arg.expr)
                }

            case .arrayAccess(let array, let index, _):
                visit(array)
                visit(index)

            case .binary(_, let lhs, let rhs, _):
                visit(lhs)
                visit(rhs)

            case .whenExpr(let subject, let branches, let elseExpr, _):
                if let subject {
                    visit(subject)
                }
                for branch in branches {
                    if let condition = branch.condition {
                        visit(condition)
                    }
                    visit(branch.body)
                }
                if let elseExpr {
                    visit(elseExpr)
                }

            case .returnExpr(let value, _):
                if let value {
                    visit(value)
                }

            case .ifExpr(let condition, let thenExpr, let elseExpr, _):
                visit(condition)
                visit(thenExpr)
                if let elseExpr {
                    visit(elseExpr)
                }

            case .tryExpr(let body, let catchClauses, let finallyExpr, _):
                visit(body)
                for catchClause in catchClauses {
                    visit(catchClause.body)
                }
                if let finallyExpr {
                    visit(finallyExpr)
                }

            case .unaryExpr(_, let operand, _):
                visit(operand)

            case .isCheck(let value, _, _, _):
                visit(value)

            case .asCast(let value, _, _, _):
                visit(value)

            case .nullAssert(let value, _):
                visit(value)

            case .safeMemberCall(let receiver, _, _, let args, _):
                visit(receiver)
                for arg in args {
                    visit(arg.expr)
                }

            case .compoundAssign(_, _, let value, _):
                visit(value)

            case .throwExpr(let value, _):
                visit(value)

            case .lambdaLiteral(_, let body, _):
                if !skipNestedClosures {
                    visit(body)
                }

            case .callableRef(let receiver, _, _):
                if let receiver {
                    visit(receiver)
                }

            case .localFunDecl(_, _, _, let body, _):
                if !skipNestedClosures {
                    visitBody(body)
                }

            case .blockExpr(let statements, let trailingExpr, _):
                for statement in statements {
                    visit(statement)
                }
                if let trailingExpr {
                    visit(trailingExpr)
                }

            case .stringTemplate(let parts, _):
                for part in parts {
                    if case .expression(let expr) = part {
                        visit(expr)
                    }
                }

            case .inExpr(let lhs, let rhs, _),
                 .notInExpr(let lhs, let rhs, _):
                visit(lhs)
                visit(rhs)

            case .intLiteral, .longLiteral, .floatLiteral, .doubleLiteral,
                 .charLiteral, .boolLiteral, .stringLiteral, .breakExpr,
                 .continueExpr, .objectLiteral, .superRef, .thisRef:
                break
            }
        }

        visit(exprID)
        return captured.sorted(by: { $0.rawValue < $1.rawValue })
    }
}
