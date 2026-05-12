/// Member-property read helpers (object members, object-literal stored
/// properties, generic stored properties, enum entry properties, external
/// members, class-name member values, const-folding) split out of
/// `CallLowerer+MemberCalls.swift`.
extension CallLowerer {
    func tryLowerObjectMemberPropertyRead(
        _ exprID: ExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let chosenSym = sema.bindings.callBindings[exprID]?.chosenCallee
        let valueSym = chosenSym ?? sema.bindings.identifierSymbol(for: exprID)
        guard let valueSym,
              let info = sema.symbols.symbol(valueSym),
              info.kind == .property,
              let parent = sema.symbols.parentSymbol(for: valueSym),
              sema.symbols.symbol(parent)?.kind == .object
        else { return nil }
        if info.flags.contains(.constValue),
           let constant = sema.symbols.constValueExprKind(for: valueSym)
        {
            let propType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSym)
                ?? sema.types.anyType
            let id = arena.appendExpr(constant, type: propType)
            instructions.append(.constValue(result: id, value: constant))
            return id
        }
        let knownNames = KnownCompilerNames(interner: interner)
        if let parentInfo = sema.symbols.symbol(parent),
           parentInfo.name == knownNames.dispatchers
        {
            let runtimeCallee: InternedString
            switch interner.resolve(info.name) {
            case "Default":
                runtimeCallee = interner.intern("kk_dispatcher_default")
            case "IO":
                runtimeCallee = interner.intern("kk_dispatcher_io")
            case "Main":
                runtimeCallee = interner.intern("kk_dispatcher_main")
            default:
                return nil
            }
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.bindings.exprTypes[exprID]
                    ?? sema.symbols.propertyType(for: valueSym)
                    ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        // STDLIB-581: Charsets.UTF_8 / ISO_8859_1 / US_ASCII / UTF_16 / ...
        if let parentInfo = sema.symbols.symbol(parent),
           parentInfo.name == knownNames.charsets
        {
            let runtimeCallee = interner.intern("kk_charset_\(interner.resolve(info.name).lowercased())")
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.bindings.exprTypes[exprID]
                    ?? sema.symbols.propertyType(for: valueSym)
                    ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        if let parentInfo = sema.symbols.symbol(parent),
           interner.resolve(parentInfo.name) == "NormalizationForms"
        {
            let runtimeCallee = interner.intern("kk_normalization_form_\(interner.resolve(info.name).lowercased())")
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.bindings.exprTypes[exprID]
                    ?? sema.symbols.propertyType(for: valueSym)
                    ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        let propType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: valueSym)
            ?? sema.types.anyType
        let id = arena.appendExpr(.symbolRef(valueSym), type: propType)
        instructions.append(.loadGlobal(result: id, symbol: valueSym))
        return wrapLateinitReadIfNeeded(
            id,
            symbol: valueSym,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func tryLowerObjectLiteralStoredPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              sema.bindings.isObjectLiteralPropertySymbol(propertySymbol)
        else {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
        if objectLiteralPropertyUsesAccessor(propertySymbol, ast: ast, sema: sema) {
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: propertySymbol,
                callee: interner.intern("get"),
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        guard let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[propertySymbol]
        else {
            return nil
        }

        let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
        instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [loweredReceiverID, offsetExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return wrapLateinitReadIfNeeded(
            result,
            symbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func tryLowerStoredMemberPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              let ownerInfo = sema.symbols.symbol(ownerSymbol),
              ownerInfo.kind == .class || ownerInfo.kind == .interface
              || ownerInfo.kind == .object,
              let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                  sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
              ]
        else {
            return nil
        }

        // Array-like types (Array, IntArray, LongArray, etc.) expose
        // properties such as `size` via runtime helper functions rather than
        // object field layout, so let the collection fallback lower them.
        let knownNames = KnownCompilerNames(interner: interner)
        if knownNames.isArrayLikeName(ownerInfo.name) {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: propertySymbol)
            ?? sema.types.anyType
        let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
        instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [loweredReceiverID, offsetExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return wrapLateinitReadIfNeeded(
            result,
            symbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func tryLowerEnumEntryPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        receiverExpr _: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let calleeStr = interner.resolve(calleeName)
        guard calleeStr == "name" || calleeStr == "ordinal" else { return nil }
        guard case let .symbolRef(entrySym) = arena.expr(loweredReceiverID),
              isEnumEntryField(entrySym, sema: sema),
              let entryInfo = sema.symbols.symbol(entrySym)
        else { return nil }
        let entryName = interner.resolve(entryInfo.name)
        let helperSuffix = calleeStr == "name" ? "$enumName" : "$enumOrdinal"
        let helperName = interner.intern(entryName + helperSuffix)
        let resultType = sema.bindings.exprTypes[exprID]
            ?? (calleeStr == "name"
                ? sema.types.make(.primitive(.string, .nonNull))
                : sema.types.make(.primitive(.int, .nonNull)))
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: helperName,
            arguments: [],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func tryLowerExternalMemberPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              let externalLinkName = sema.symbols.externalLinkName(for: propertySymbol),
              !externalLinkName.isEmpty
        else {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: propertySymbol)
            ?? sema.types.anyType
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: propertySymbol,
            callee: interner.intern(externalLinkName),
            arguments: [loweredReceiverID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return wrapLateinitReadIfNeeded(
            result,
            symbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func objectLiteralPropertyUsesAccessor(
        _ propertySymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule
    ) -> Bool {
        for rawDecl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(rawDecl))
            guard sema.bindings.declSymbols[declID] == propertySymbol,
                  let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            return propertyDecl.getter != nil || propertyDecl.delegateExpression != nil
        }
        return false
    }

    func tryLowerClassNameMemberValueExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              sema.bindings.callBindings[exprID] == nil,
              let receiverExprNode = ast.arena.expr(receiverExpr),
              case .nameRef = receiverExprNode,
              let receiverSymbolID = sema.bindings.identifierSymbol(for: receiverExpr),
              let receiverSymbol = sema.symbols.symbol(receiverSymbolID)
        else {
            return nil
        }
        guard receiverSymbol.kind == .class || receiverSymbol.kind == .interface || receiverSymbol.kind == .enumClass,
              let valueSymbolID = sema.bindings.identifierSymbol(for: exprID),
              let valueSymbol = sema.symbols.symbol(valueSymbolID)
        else {
            return nil
        }

        switch valueSymbol.kind {
        case .property where valueSymbol.flags.contains(.constValue):
            guard let constant = sema.symbols.constValueExprKind(for: valueSymbolID) else {
                return nil
            }
            let valueType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSymbolID)
                ?? sema.types.anyType
            let valueID = arena.appendExpr(constant, type: valueType)
            instructions.append(.constValue(result: valueID, value: constant))
            return valueID

        case .field:
            guard isEnumEntryField(valueSymbolID, sema: sema) else {
                return nil
            }
            let valueType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSymbolID)
                ?? sema.types.anyType
            let valueID = arena.appendExpr(.symbolRef(valueSymbolID), type: valueType)
            instructions.append(.constValue(result: valueID, value: .symbolRef(valueSymbolID)))
            return valueID

        case .object:
            let valueType = sema.bindings.exprTypes[exprID] ?? sema.types.make(.classType(ClassType(
                classSymbol: valueSymbolID,
                args: [],
                nullability: .nonNull
            )))
            let valueID = arena.appendExpr(.symbolRef(valueSymbolID), type: valueType)
            instructions.append(.constValue(result: valueID, value: .symbolRef(valueSymbolID)))
            return valueID

        default:
            return nil
        }
    }

    func isEnumEntryField(_ fieldSymbol: SymbolID, sema: SemaModule) -> Bool {
        if let parentSymbol = sema.symbols.parentSymbol(for: fieldSymbol),
           sema.symbols.symbol(parentSymbol)?.kind == .enumClass
        {
            return true
        }
        guard let field = sema.symbols.symbol(fieldSymbol),
              field.kind == .field,
              field.fqName.count >= 2
        else {
            return false
        }
        let ownerFQName = Array(field.fqName.dropLast())
        return sema.symbols.lookupAll(fqName: ownerFQName).contains { candidate in
            sema.symbols.symbol(candidate)?.kind == .enumClass
        }
    }
}
