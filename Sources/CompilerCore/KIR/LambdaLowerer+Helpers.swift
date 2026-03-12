import Foundation

extension LambdaLowerer {
    func syntheticLambdaName(for exprID: ExprID, interner: StringInterner) -> InternedString {
        interner.intern("kk_lambda_\(exprID.rawValue)")
    }

    func syntheticLambdaParamSymbol(lambdaExprID: ExprID, paramIndex: Int) -> SymbolID {
        boundedNegativeSyntheticSymbol(
            Int64(-1_000_000)
                - Int64(lambdaExprID.rawValue) * 256
                - Int64(paramIndex)
        )
    }

    /// Closure param for single-param lambdas passed to C HOFs (filter, map, etc.).
    /// Runtime expects (closureRaw, elem, outThrown); this receives closureRaw.
    func syntheticLambdaClosureParamSymbol(lambdaExprID: ExprID) -> SymbolID {
        syntheticLambdaParamSymbol(lambdaExprID: lambdaExprID, paramIndex: -1)
    }

    func syntheticLambdaCaptureParamSymbol(lambdaExprID: ExprID, captureIndex: Int) -> SymbolID {
        boundedNegativeSyntheticSymbol(
            Int64(-2_000_000)
                - Int64(lambdaExprID.rawValue) * 256
                - Int64(captureIndex)
        )
    }

    private func boundedNegativeSyntheticSymbol(_ rawValue: Int64) -> SymbolID {
        let bounded = min(Int64(-2), max(Int64(Int32.min), rawValue))
        return SymbolID(rawValue: Int32(bounded))
    }

    func callableTargetName(
        for symbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        if let externalLinkName = sema.symbols.externalLinkName(for: symbol),
           !externalLinkName.isEmpty
        {
            return interner.intern(externalLinkName)
        }
        return sema.symbols.symbol(symbol)?.name ?? interner.intern("kk_unknown_callable")
    }

    func typeForSymbolReference(_ symbol: SymbolID, sema: SemaModule) -> TypeID {
        if let functionSignature = sema.symbols.functionSignature(for: symbol) {
            return sema.types.make(
                .functionType(
                    FunctionType(
                        receiver: functionSignature.receiverType,
                        params: functionSignature.parameterTypes,
                        returnType: functionSignature.returnType,
                        isSuspend: functionSignature.isSuspend,
                        nullability: .nonNull
                    )
                )
            )
        }
        if let propertyType = sema.symbols.propertyType(for: symbol) {
            return propertyType
        }
        if let valueParameterType = typeForValueParameterSymbol(symbol, sema: sema) {
            return valueParameterType
        }
        return sema.types.anyType
    }

    private func typeForValueParameterSymbol(_ symbol: SymbolID, sema: SemaModule) -> TypeID? {
        let kinds: [SymbolKind] = [.function, .constructor]
        for kind in kinds {
            for candidateID in sema.symbols.symbols(ofKind: kind) {
                guard let signature = sema.symbols.functionSignature(for: candidateID),
                      let index = signature.valueParameterSymbols.firstIndex(of: symbol),
                      index < signature.parameterTypes.count
                else {
                    continue
                }
                return signature.parameterTypes[index]
            }
        }
        return nil
    }

    func resolveCallableRefTargetSymbol(
        exprID: ExprID,
        receiverExpr: ExprID?,
        memberName: InternedString,
        sema: SemaModule
    ) -> SymbolID? {
        if let bound = sema.bindings.identifierSymbols[exprID] {
            return bound
        }

        var candidates: [SymbolID] = []
        if let receiverExpr,
           let receiverType = sema.bindings.exprTypes[receiverExpr],
           let receiverSymbol = nominalSymbol(for: receiverType, types: sema.types)
        {
            var ownerQueue: [SymbolID] = [receiverSymbol]
            var visitedOwners: Set<SymbolID> = []
            while let owner = ownerQueue.first {
                ownerQueue.removeFirst()
                guard visitedOwners.insert(owner).inserted,
                      let ownerSymbol = sema.symbols.symbol(owner)
                else {
                    continue
                }
                let fqName = ownerSymbol.fqName + [memberName]
                let ownerCandidates = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: symbolID)
                    else {
                        return false
                    }
                    return signature.receiverType != nil
                }
                candidates.append(contentsOf: ownerCandidates)
                ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
            }

            if candidates.isEmpty {
                let extensionCandidates = sema.symbols.lookupAll(fqName: [memberName]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.receiverType != nil
                    else {
                        return false
                    }
                    return true
                }
                candidates.append(contentsOf: extensionCandidates)
            }
        } else {
            candidates = sema.symbols.lookupAll(fqName: [memberName]).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        }

        if candidates.isEmpty {
            candidates = sema.symbols.lookupByShortName(memberName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        }

        return candidates.sorted(by: { lhs, rhs in
            lhs.rawValue < rhs.rawValue
        }).first
    }

    func nominalSymbol(for typeID: TypeID, types: TypeSystem) -> SymbolID? {
        guard case let .classType(classType) = types.kind(of: typeID) else {
            return nil
        }
        return classType.classSymbol
    }

    func computeCaptureSymbolsForLambda(
        lambdaExprID: ExprID,
        lambdaParamCount: Int,
        lambdaBodyExprID: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> [SymbolID] {
        if let boundCaptures = sema.bindings.captureSymbolsByExpr[lambdaExprID] {
            var captures = uniqueSymbolsPreservingOrder(boundCaptures).filter { symbol in
                canCaptureSymbolForLambda(
                    symbol,
                    lambdaExprID: lambdaExprID,
                    lambdaParamCount: lambdaParamCount,
                    sema: sema
                )
            }
            if let receiverSymbol = driver.ctx.activeImplicitReceiverSymbol(),
               containsImplicitReceiverReference(in: lambdaBodyExprID, ast: ast)
               || containsImplicitReceiverMemberAccess(in: lambdaBodyExprID, ast: ast, sema: sema),
               canCaptureSymbolForLambda(
                   receiverSymbol,
                   lambdaExprID: lambdaExprID,
                   lambdaParamCount: lambdaParamCount,
                   sema: sema
               ),
               !captures.contains(receiverSymbol)
            {
                captures.append(receiverSymbol)
            }
            return captures
        }
        return lexicalCaptureSymbolsForLambda(
            lambdaExprID: lambdaExprID,
            lambdaParamCount: lambdaParamCount,
            lambdaBodyExprID: lambdaBodyExprID,
            ast: ast,
            sema: sema
        )
    }

    private func lexicalCaptureSymbolsForLambda(
        lambdaExprID: ExprID,
        lambdaParamCount: Int,
        lambdaBodyExprID: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> [SymbolID] {
        var referenced: [SymbolID] = []
        var seen: Set<SymbolID> = []
        collectBoundIdentifierSymbols(
            in: lambdaBodyExprID,
            ast: ast,
            sema: sema,
            referenced: &referenced,
            seen: &seen
        )
        var captures = referenced.filter { symbol in
            canCaptureSymbolForLambda(
                symbol,
                lambdaExprID: lambdaExprID,
                lambdaParamCount: lambdaParamCount,
                sema: sema
            )
        }
        if let receiverSymbol = driver.ctx.activeImplicitReceiverSymbol(),
           containsImplicitReceiverReference(in: lambdaBodyExprID, ast: ast)
           || containsImplicitReceiverMemberAccess(in: lambdaBodyExprID, ast: ast, sema: sema),
           canCaptureSymbolForLambda(
               receiverSymbol,
               lambdaExprID: lambdaExprID,
               lambdaParamCount: lambdaParamCount,
               sema: sema
           ),
           !captures.contains(receiverSymbol)
        {
            captures.append(receiverSymbol)
        }
        return captures
    }

    /// STDLIB-004: Check if an expression tree contains any implicit receiver
    /// member accesses (bare name references resolved through implicitReceiverType).
    /// Mirrors `containsImplicitReceiverReference` for all AST node types.
    func containsImplicitReceiverMemberAccess(in exprID: ExprID, ast: ASTModule, sema: SemaModule) -> Bool {
        if let symbolID = sema.bindings.identifierSymbols[exprID],
           let symbol = sema.symbols.symbol(symbolID),
           symbol.kind == .property || symbol.kind == .field,
           let parentID = sema.symbols.parentSymbol(for: symbolID),
           let parent = sema.symbols.symbol(parentID),
           parent.kind == .class || parent.kind == .object || parent.kind == .interface
        {
            return true
        }
        if sema.bindings.implicitReceiverMemberNames[exprID] != nil {
            return true
        }
        guard let expr = ast.arena.expr(exprID) else {
            return false
        }
        let check = { (id: ExprID) -> Bool in
            self.containsImplicitReceiverMemberAccess(in: id, ast: ast, sema: sema)
        }
        switch expr {
        case let .blockExpr(stmts, trailing, _):
            return stmts.contains(where: check) || trailing.map(check) ?? false
        case let .call(callee, _, args, _):
            return check(callee) || args.contains { check($0.expr) }
        case let .memberCall(receiver, _, _, args, _),
             let .safeMemberCall(receiver, _, _, args, _):
            return check(receiver) || args.contains { check($0.expr) }
        case let .binary(_, lhs, rhs, _):
            return check(lhs) || check(rhs)
        case let .ifExpr(cond, thenExpr, elseExpr, _):
            return check(cond) || check(thenExpr) || elseExpr.map(check) ?? false
        case let .whenExpr(subject, branches, elseBody, _):
            return checkWhenExprChildren(subject: subject, branches: branches, elseBody: elseBody, check: check)
        case let .returnExpr(value, _, _):
            return value.map(check) ?? false
        case let .unaryExpr(_, operand, _),
             let .nullAssert(operand, _),
             let .throwExpr(operand, _):
            return check(operand)
        case let .isCheck(operand, _, _, _),
             let .asCast(operand, _, _, _):
            return check(operand)
        case let .tryExpr(body, _, finallyBody, _):
            return check(body) || finallyBody.map(check) ?? false
        case let .lambdaLiteral(_, bodyExpr, _, _):
            return check(bodyExpr)
        case let .indexedAccess(receiver, indices, _):
            return check(receiver) || indices.contains(where: check)
        case let .stringTemplate(parts, _):
            return checkStringTemplateParts(parts, check: check)
        case let .localDecl(_, _, _, initializer, _, _):
            return initializer.map(check) ?? false
        case .localAssign, .compoundAssign, .memberAssign, .indexedAssign, .indexedCompoundAssign:
            return checkAssignmentChildren(expr, check: check)
        case let .inExpr(lhs, rhs, _),
             let .notInExpr(lhs, rhs, _):
            return check(lhs) || check(rhs)
        case let .callableRef(receiver, _, _):
            return receiver.map(check) ?? false
        case let .localFunDecl(_, _, _, body, _):
            return checkFunctionBody(body, check: check)
        case let .forExpr(_, iterable, body, _, _):
            return check(iterable) || check(body)
        case let .whileExpr(condition, body, _, _):
            return check(condition) || check(body)
        case let .doWhileExpr(body, condition, _, _):
            return check(body) || check(condition)
        default:
            return false
        }
    }

    private func checkFunctionBody(
        _ body: FunctionBody,
        check: (ExprID) -> Bool
    ) -> Bool {
        switch body {
        case let .block(stmts, _): stmts.contains(where: check)
        case let .expr(bodyExpr, _): check(bodyExpr)
        case .unit: false
        }
    }

    private func checkStringTemplateParts(
        _ parts: [StringTemplatePart],
        check: (ExprID) -> Bool
    ) -> Bool {
        parts.contains { part in
            if case let .expression(exprID) = part {
                return check(exprID)
            }
            return false
        }
    }

    private func checkAssignmentChildren(
        _ expr: Expr,
        check: (ExprID) -> Bool
    ) -> Bool {
        switch expr {
        case let .localAssign(_, valueExpr, _):
            check(valueExpr)
        case let .compoundAssign(_, _, valueExpr, _):
            check(valueExpr)
        case let .memberAssign(receiver, _, value, _):
            check(receiver) || check(value)
        case let .indexedAssign(receiver, indices, value, _):
            check(receiver) || indices.contains(where: check) || check(value)
        case let .indexedCompoundAssign(_, receiver, indices, value, _):
            check(receiver) || indices.contains(where: check) || check(value)
        default:
            false
        }
    }

    private func checkWhenExprChildren(
        subject: ExprID?,
        branches: [WhenBranch],
        elseBody: ExprID?,
        check: (ExprID) -> Bool
    ) -> Bool {
        subject.map(check) ?? false
            || branches.contains { branch in
                branch.conditions.contains(where: check) || check(branch.body)
            }
            || elseBody.map(check) ?? false
    }

    func captureValueExpr(
        for symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if let localValue = driver.ctx.localValue(for: symbol) {
            return localValue
        }
        if symbol == driver.ctx.activeImplicitReceiverSymbol(),
           let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
        {
            return receiverExprID
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol),
              semanticSymbol.kind == .valueParameter
        else {
            return nil
        }

        let symbolType = typeForSymbolReference(symbol, sema: sema)
        let symbolExpr = arena.appendExpr(.symbolRef(symbol), type: symbolType)
        instructions.append(.constValue(result: symbolExpr, value: .symbolRef(symbol)))
        return symbolExpr
    }
}
