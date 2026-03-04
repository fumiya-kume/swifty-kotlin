import Foundation

/// Delegate class for KIR lowering: MemberLowerer.
/// Holds an unowned reference to the driver for mutual recursion.
final class MemberLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func lowerMemberDecls(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) -> (directMembers: [KIRDeclID], allDecls: [KIRDeclID]) {
        var directMembers: [KIRDeclID] = []
        var allDecls: [KIRDeclID] = []

        for declID in memberFunctions {
            guard let decl = ast.arena.decl(declID),
                  case let .funDecl(function) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            driver.ctx.resetScopeForFunction()
            driver.ctx.beginCallableLoweringScope()
            driver.ctx.currentFunctionSymbol = symbol

            let signature = sema.symbols.functionSignature(for: symbol)
            var params: [KIRParameter] = []
            if let signature {
                if let receiverType = signature.receiverType {
                    let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol)
                    params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                    driver.ctx.currentImplicitReceiverSymbol = receiverSymbol
                    driver.ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                }
                params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                    KIRParameter(symbol: pair.0, type: pair.1)
                })
            }
            if function.isInline, let signature,
               !signature.reifiedTypeParameterIndices.isEmpty {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for index in signature.reifiedTypeParameterIndices.sorted() {
                    guard index < signature.typeParameterSymbols.count else { continue }
                    let typeParamSymbol = signature.typeParameterSymbols[index]
                    let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                    params.append(KIRParameter(symbol: tokenSymbol, type: intType))
                }
            }
            let returnType = signature?.returnType ?? sema.types.unitType
            var body: [KIRInstruction] = [.beginBlock]
            if let receiverExpr = driver.ctx.currentImplicitReceiverExprID,
               let receiverSymbol = driver.ctx.currentImplicitReceiverSymbol {
                body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
            }
            switch function.body {
            case let .block(exprIDs, _):
                var lastValue: KIRExprID?
                var terminatedByReturn = false
                for exprID in exprIDs {
                    if let expr = ast.arena.expr(exprID),
                       case let .returnExpr(value, _, _) = expr {
                        if let value {
                            let lowered = driver.lowerExpr(
                                value,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &body
                            )
                            body.append(.returnValue(lowered))
                        } else {
                            body.append(.returnUnit)
                        }
                        terminatedByReturn = true
                        break
                    }
                    lastValue = driver.lowerExpr(
                        exprID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &body
                    )
                }
                if !terminatedByReturn {
                    if let lastValue {
                        body.append(.returnValue(lastValue))
                    } else {
                        body.append(.returnUnit)
                    }
                }
            case let .expr(exprID, _):
                let value = driver.lowerExpr(
                    exprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &body
                )
                body.append(.returnValue(value))
            case .unit:
                body.append(.returnUnit)
            }
            body.append(.endBlock)
            let kirID = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: symbol,
                        name: function.name,
                        params: params,
                        returnType: returnType,
                        body: body,
                        isSuspend: function.isSuspend,
                        isInline: function.isInline
                    )
                )
            )
            directMembers.append(kirID)
            allDecls.append(kirID)
            if let defaults = driver.ctx.functionDefaultArgumentsBySymbol[symbol],
               let sig = signature {
                let stubID = driver.callSupportLowerer.generateDefaultStubFunction(
                    originalSymbol: symbol,
                    originalName: function.name,
                    signature: sig,
                    defaultExpressions: defaults,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers
                )
                allDecls.append(stubID)
            }
            allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
            driver.ctx.currentImplicitReceiverExprID = nil
            driver.ctx.currentImplicitReceiverSymbol = nil
            driver.ctx.currentFunctionSymbol = nil
        }

        for declID in memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType

            // Getter-only computed properties (`val x: T get() = expr`) have no
            // storage — skip emitting a KIRGlobal so no backing field is generated
            // in codegen.  The getter accessor function alone is sufficient.
            let isGetterOnlyComputed = propertyDecl.getter != nil
                && propertyDecl.setter == nil
                && propertyDecl.initializer == nil
                && propertyDecl.delegateExpression == nil

            if !isGetterOnlyComputed {
                let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propType)))
                directMembers.append(kirID)
                allDecls.append(kirID)
            }

            // Emit backing field global for properties with custom accessors.
            if let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) {
                let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol) ?? propType
                let backingFieldKirID = arena.appendDecl(
                    .global(KIRGlobal(symbol: backingFieldSymbol, type: backingFieldType))
                )
                allDecls.append(backingFieldKirID)
            }

            // Lower getter body as a KIR accessor function.
            if let getter = propertyDecl.getter, getter.body != .unit {
                lowerAccessorBody(
                    accessorBody: getter.body,
                    propertySymbol: symbol,
                    propertyType: propType,
                    accessorKind: .getter,
                    setterParamName: nil,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            }

            // Lower setter body as a KIR accessor function.
            if let setter = propertyDecl.setter, setter.body != .unit {
                lowerAccessorBody(
                    accessorBody: setter.body,
                    propertySymbol: symbol,
                    propertyType: propType,
                    accessorKind: .setter,
                    setterParamName: setter.parameterName,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            }

            // Lower delegated property: emit delegate storage global and
            // synthesise getter (and setter for var) that call getValue/setValue
            // on the delegate instance.
            if propertyDecl.delegateExpression != nil {
                let delegateStorageSymbol: SymbolID
                if let existingStorage = sema.symbols.delegateStorageSymbol(for: symbol) {
                    delegateStorageSymbol = existingStorage
                } else {
                    let delegateStorageName = interner.intern("$delegate_\(interner.resolve(propertyDecl.name))")
                    let delegateStorageFQName = (sema.symbols.symbol(symbol)?.fqName.dropLast() ?? []) + [delegateStorageName]
                    delegateStorageSymbol = sema.symbols.define(
                        kind: .field,
                        name: delegateStorageName,
                        fqName: Array(delegateStorageFQName),
                        declSite: propertyDecl.range,
                        visibility: .private,
                        flags: []
                    )
                }
                let delegateType = sema.types.anyType
                let delegateKirID = arena.appendDecl(
                    .global(KIRGlobal(symbol: delegateStorageSymbol, type: delegateType))
                )
                allDecls.append(delegateKirID)

                // Synthesise getter: calls getValue on the delegate storage.
                lowerDelegateAccessor(
                    propertySymbol: symbol,
                    propertyType: propType,
                    delegateStorageSymbol: delegateStorageSymbol,
                    accessorKind: .getter,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    allDecls: &allDecls
                )

                // Synthesise setter for var properties: calls setValue on the delegate.
                if propertyDecl.isVar {
                    lowerDelegateAccessor(
                        propertySymbol: symbol,
                        propertyType: propType,
                        delegateStorageSymbol: delegateStorageSymbol,
                        accessorKind: .setter,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                }
            }
        }

        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            switch decl {
            case let .classDecl(nested):
                var nestedAllObjects = nested.nestedObjects
                if let companionDeclID = nested.companionObject {
                    nestedAllObjects.append(companionDeclID)
                }
                let (nestedDirect, nestedAll) = lowerMemberDecls(
                    memberFunctions: nested.memberFunctions,
                    memberProperties: nested.memberProperties,
                    nestedClasses: nested.nestedClasses,
                    nestedObjects: nestedAllObjects,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers
                )
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: nestedDirect)))
                directMembers.append(kirID)
                allDecls.append(kirID)
                allDecls.append(contentsOf: nestedAll)
            case let .interfaceDecl(nestedInterface):
                // Interface properties have no backing storage; pass empty list.
                var nestedInterfaceAllObjects = nestedInterface.nestedObjects
                if let companionDeclID = nestedInterface.companionObject {
                    nestedInterfaceAllObjects.append(companionDeclID)
                }
                let (nestedDirect, nestedAll) = lowerMemberDecls(
                    memberFunctions: nestedInterface.memberFunctions,
                    memberProperties: [],
                    nestedClasses: nestedInterface.nestedClasses,
                    nestedObjects: nestedInterfaceAllObjects,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers
                )
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: nestedDirect)))
                directMembers.append(kirID)
                allDecls.append(kirID)
                allDecls.append(contentsOf: nestedAll)
            default:
                continue
            }
        }

        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case let .objectDecl(nested) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            let (nestedDirect, nestedAll) = lowerMemberDecls(
                memberFunctions: nested.memberFunctions,
                memberProperties: nested.memberProperties,
                nestedClasses: nested.nestedClasses,
                nestedObjects: nested.nestedObjects,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: nestedDirect)))
            directMembers.append(kirID)
            allDecls.append(kirID)
            allDecls.append(contentsOf: nestedAll)
        }

        return (directMembers, allDecls)
    }

    /// Synthesise a getter or setter function for a delegated property.
    ///
    /// Getter emits: `return $delegate_x.getValue(thisRef, KProperty("x"))`
    /// Setter emits: `$delegate_x.setValue(thisRef, KProperty("x"), value)`
    ///
    /// The actual `getValue`/`setValue` calls use the delegate storage symbol
    /// so that `PropertyLoweringPass` can later rewrite them to
    /// `kk_property_access`.
    func lowerDelegateAccessor(
        propertySymbol: SymbolID,
        propertyType: TypeID,
        delegateStorageSymbol: SymbolID,
        accessorKind: PropertyAccessorKind,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        let shared = KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: [:]
        )
        lowerDelegateAccessor(
            propertySymbol: propertySymbol,
            propertyType: propertyType,
            delegateStorageSymbol: delegateStorageSymbol,
            accessorKind: accessorKind,
            shared: shared,
            allDecls: &allDecls
        )
    }

    /// Lower a property getter or setter body as a synthetic KIR function.
    ///
    /// Getter signature: `(<receiver>) -> PropertyType`
    /// Setter signature: `(<receiver>, value: PropertyType) -> Unit`
    func lowerAccessorBody(
        accessorBody: FunctionBody,
        propertySymbol: SymbolID,
        propertyType: TypeID,
        accessorKind: PropertyAccessorKind,
        setterParamName: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        allDecls: inout [KIRDeclID]
    ) {
        let shared = KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        lowerAccessorBody(
            accessorBody: accessorBody,
            propertySymbol: propertySymbol,
            propertyType: propertyType,
            accessorKind: accessorKind,
            setterParamName: setterParamName,
            shared: shared,
            allDecls: &allDecls
        )
    }
}
