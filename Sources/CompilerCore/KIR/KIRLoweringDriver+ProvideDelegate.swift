import Foundation

// MARK: - provideDelegate operator support (PROP-007)

// swiftlint:disable trailing_comma
extension KIRLoweringDriver {
    /// Checks whether the delegate expression type defines a `provideDelegate` operator function.
    func checkHasProvideDelegate(
        delegateExprType: TypeID?,
        shared: KIRLoweringSharedContext
    ) -> Bool {
        let sema = shared.sema
        let interner = shared.interner
        let provideDelegateName = interner.intern("provideDelegate")
        guard let delType = delegateExprType else { return false }
        let typeKind = sema.types.kind(of: delType)
        switch typeKind {
        case let .classType(classType):
            guard let sym = sema.symbols.symbol(classType.classSymbol) else { return false }
            let memberSymbols = sema.symbols.children(ofFQName: sym.fqName)
            return memberSymbols.contains { memberID in
                guard let member = sema.symbols.symbol(memberID) else { return false }
                return member.name == provideDelegateName && member.kind == .function
            }
        default:
            return false
        }
    }

    /// Emits a `kk_kproperty_stub_create(name, returnType)` call and returns the result expression ID.
    func emitKPropertyStubCreate(
        propertyName: InternedString,
        propertyType: TypeID,
        shared: KIRLoweringSharedContext,
        emit body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let interner = shared.interner
        let arena = shared.arena
        let propertyNameExprID = arena.appendExpr(
            .stringLiteral(propertyName),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        body.append(.constValue(result: propertyNameExprID, value: .stringLiteral(propertyName)))
        let returnTypeSig = interner.intern(sema.types.renderType(propertyType))
        let returnTypeExprID = arena.appendExpr(
            .stringLiteral(returnTypeSig),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        body.append(.constValue(result: returnTypeExprID, value: .stringLiteral(returnTypeSig)))
        let kPropertyExprID = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: sema.types.anyType
        )
        body.append(
            .call(
                symbol: nil,
                callee: interner.intern("kk_kproperty_stub_create"),
                arguments: [propertyNameExprID, returnTypeExprID],
                result: kPropertyExprID,
                canThrow: false,
                thrownResult: nil
            )
        )
        return kPropertyExprID
    }

    /// Emits the full provideDelegate flow for top-level properties: store raw delegate,
    /// build thisRef + KProperty stub, call provideDelegate, wrap result in kk_custom_delegate_create.
    func emitProvideDelegateInit(
        delegateObjExpr: KIRExprID,
        symbol: SymbolID,
        delegateStorageSymbol: SymbolID,
        delegateType: TypeID,
        shared: KIRLoweringSharedContext,
        emit initInstructions: inout KIRLoweringEmitContext
    ) {
        let arena = shared.arena
        let sema = shared.sema
        let interner = shared.interner

        // Store the raw delegate so we can call provideDelegate on it.
        initInstructions.append(.storeGlobal(value: delegateObjExpr, symbol: delegateStorageSymbol))

        // Build thisRef (null for top-level properties).
        let thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        initInstructions.append(.constValue(result: thisRefExprID, value: .null))

        // Build a KProperty<*> stub.
        let propertyName = sema.symbols.symbol(symbol)?.name ?? interner.intern("")
        let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
        let kPropertyExprID = emitKPropertyStubCreate(
            propertyName: propertyName, propertyType: propType,
            shared: shared, emit: &initInstructions
        )

        // Call provideDelegate(thisRef, kProperty) on the raw delegate.
        let provideDelegateName = interner.intern("provideDelegate")
        let provideDelegateResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: sema.types.anyType
        )
        initInstructions.append(
            .call(
                symbol: delegateStorageSymbol,
                callee: provideDelegateName,
                arguments: [thisRefExprID, kPropertyExprID],
                result: provideDelegateResult,
                canThrow: false,
                thrownResult: nil
            )
        )

        // Wrap the provideDelegate result in kk_custom_delegate_create.
        let wrappedResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)), type: delegateType
        )
        initInstructions.append(.call(
            symbol: nil, callee: interner.intern("kk_custom_delegate_create"),
            arguments: [provideDelegateResult],
            result: wrappedResult, canThrow: false, thrownResult: nil
        ))
        initInstructions.append(.storeGlobal(value: wrappedResult, symbol: delegateStorageSymbol))
    }

    /// Emits the simple delegate init: just wrap in kk_custom_delegate_create.
    func emitSimpleDelegateInit(
        delegateObjExpr: KIRExprID,
        delegateStorageSymbol: SymbolID,
        delegateType: TypeID,
        shared: KIRLoweringSharedContext,
        emit initInstructions: inout KIRLoweringEmitContext
    ) {
        let arena = shared.arena
        let interner = shared.interner
        let createResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)), type: delegateType
        )
        initInstructions.append(.call(
            symbol: nil, callee: interner.intern("kk_custom_delegate_create"),
            arguments: [delegateObjExpr],
            result: createResult, canThrow: false, thrownResult: nil
        ))
        initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))
    }
}

// MARK: - ABILoweringPass helpers

extension ABILoweringPass {
    /// Returns the set of KProperty stub runtime callee names for the non-throwing callees set.
    static func kPropertyStubCallees(_ interner: StringInterner) -> Set<InternedString> {
        [
            interner.intern("kk_kproperty_stub_create"),
            interner.intern("kk_kproperty_stub_name"),
            interner.intern("kk_kproperty_stub_return_type"),
        ]
    }
}

// swiftlint:enable trailing_comma
