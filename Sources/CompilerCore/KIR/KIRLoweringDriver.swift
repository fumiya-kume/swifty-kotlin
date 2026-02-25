import Foundation

/// Dispatch hub for KIR lowering. Replaces the monolithic extension-based splitting
/// of `BuildKIRPhase` with independent delegate classes.
///
/// Each delegate holds an `unowned` back-reference to this driver so that mutually
/// recursive calls (e.g. `lowerExpr` → `lowerCallExpr` → `lowerExpr`) can be
/// dispatched through the driver rather than sharing a single fat class instance.
final class KIRLoweringDriver {
    let ctx: KIRLoweringContext

    // Delegates (lazy to break initialization ordering; each holds unowned back-reference)
    private(set) lazy var exprLowerer = ExprLowerer(driver: self)
    private(set) lazy var callLowerer = CallLowerer(driver: self)
    private(set) lazy var controlFlowLowerer = ControlFlowLowerer(driver: self)
    private(set) lazy var memberLowerer = MemberLowerer(driver: self)
    private(set) lazy var lambdaLowerer = LambdaLowerer(driver: self)
    private(set) lazy var objectLiteralLowerer = ObjectLiteralLowerer(driver: self)
    private(set) lazy var callSupportLowerer = CallSupportLowerer(driver: self)

    // Stateless utilities (no back-reference needed)
    let constantCollector = ConstantCollector()

    init(ctx: KIRLoweringContext) {
        self.ctx = ctx
    }

    // MARK: - Main Recursive Dispatch Entry Point

    func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        return exprLowerer.lowerExpr(
            exprID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }

    // MARK: - Module Lowering

    func lowerModule(
        ast: ASTModule,
        sema: SemaModule,
        compilationCtx: CompilationContext
    ) -> KIRModule {
        ctx.resetModuleState()
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: sema)

        let arena = KIRArena()
        var files: [KIRFile] = []
        var sourceByFileID: [Int32: String] = [:]
        for file in ast.files {
            let contents = compilationCtx.sourceManager.contents(of: file.fileID)
            sourceByFileID[file.fileID.rawValue] = String(data: contents, encoding: .utf8) ?? ""
        }
        let propertyConstantInitializers = constantCollector.collectPropertyConstantInitializers(
            ast: ast,
            sema: sema,
            interner: compilationCtx.interner,
            sourceByFileID: sourceByFileID
        )
        ctx.functionDefaultArgumentsBySymbol = callSupportLowerer.collectFunctionDefaultArgumentExpressions(
            ast: ast,
            sema: sema
        )

        // Collect all top-level property init instructions (regular + delegate) in declaration order.
        // Using a single array ensures Kotlin's strict declaration-order initialization guarantee.
        var allTopLevelInitInstructions: [KIRInstruction] = []
        // Maps property symbol → copy-target KIRExprID that holds the delegate handle.
        // The LLVM backend resolves copy targets via alloca/load, so we use the copy
        // target expr ID (not a symbolRef) as the argument in getValue calls.
        var delegateHandleExprByPropertySymbol: [SymbolID: KIRExprID] = [:]

        for file in ast.sortedFiles {
            var declIDs: [KIRDeclID] = []
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      let symbol = sema.bindings.declSymbols[declID] else {
                    continue
                }

                switch decl {
                case .classDecl(let classDecl):
                    // Collect nested objects including the companion object
                    var allNestedObjects = classDecl.nestedObjects
                    if let companionDeclID = classDecl.companionObject {
                        allNestedObjects.append(companionDeclID)
                    }
                    let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
                        memberFunctions: classDecl.memberFunctions,
                        memberProperties: classDecl.memberProperties,
                        nestedClasses: classDecl.nestedClasses,
                        nestedObjects: allNestedObjects,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: compilationCtx.interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)

                    let ctorFQName = (sema.symbols.symbol(symbol)?.fqName ?? []) + [compilationCtx.interner.intern("<init>")]
                    let ctorSymbols = sema.symbols.lookupAll(
                        fqName: ctorFQName
                    )
                    for ctorSymbol in ctorSymbols {
                        guard let signature = sema.symbols.functionSignature(for: ctorSymbol) else {
                            continue
                        }
                        ctx.resetScopeForFunction()
                        ctx.beginCallableLoweringScope()

                        let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: ctorSymbol)
                        var params = [KIRParameter(symbol: receiverSymbol, type: signature.returnType)]
                        ctx.currentImplicitReceiverSymbol = receiverSymbol
                        ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: signature.returnType)

                        params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                            KIRParameter(symbol: pair.0, type: pair.1)
                        })
                        let returnType = signature.returnType
                        var body: [KIRInstruction] = [.beginBlock]

                        if let receiverExpr = ctx.currentImplicitReceiverExprID,
                           let receiverSym = ctx.currentImplicitReceiverSymbol {
                            body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSym)))
                        }

                        let isSecondary = sema.symbols.symbol(ctorSymbol)?.declSite != classDecl.range

                        if !isSecondary {
                            // Emit member property initializers as field stores.
                            for propDeclID in classDecl.memberProperties {
                                guard let propDecl = ast.arena.decl(propDeclID),
                                      case .propertyDecl(let prop) = propDecl,
                                      let propSymbol = sema.bindings.declSymbols[propDeclID] else {
                                    continue
                                }

                                // Handle delegated property initialisation:
                                // lower the delegate expression and store it in
                                // the $delegate_ storage field.  If the delegate
                                // type exposes a `provideDelegate` operator, wrap
                                // the initial value in a provideDelegate call;
                                // otherwise store the delegate value directly.
                                if let delegateExpr = prop.delegateExpression {
                                    let delegateStorageSym = sema.symbols.delegateStorageSymbol(for: propSymbol)
                                    let delegateValue = lowerExpr(
                                        delegateExpr,
                                        ast: ast,
                                        sema: sema,
                                        arena: arena,
                                        interner: compilationCtx.interner,
                                        propertyConstantInitializers: propertyConstantInitializers,
                                        instructions: &body
                                    )

                                    // Check whether the delegate type defines a
                                    // provideDelegate operator.  Only emit the call
                                    // when it is actually available; otherwise store
                                    // the raw delegate value directly.
                                    let delegateExprType = sema.bindings.exprType(for: delegateExpr)
                                    let provideDelegateName = compilationCtx.interner.intern("provideDelegate")
                                    let hasProvideDelegate: Bool = {
                                        guard let delegateType = delegateExprType else { return false }
                                        // Look up provideDelegate on the delegate's nominal type.
                                        let typeKind = sema.types.kind(of: delegateType)
                                        switch typeKind {
                                        case .classType(let ct):
                                            guard let sym = sema.symbols.symbol(ct.classSymbol) else { return false }
                                            let memberSymbols = sema.symbols.children(ofFQName: sym.fqName)
                                            return memberSymbols.contains { memberID in
                                                guard let member = sema.symbols.symbol(memberID) else { return false }
                                                return member.name == provideDelegateName
                                                    && member.kind == .function
                                            }
                                        default:
                                            return false
                                        }
                                    }()

                                    let valueToStore: KIRExprID
                                    if hasProvideDelegate, let storageSym = delegateStorageSym {
                                        // First, store the raw delegate value so we
                                        // have a receiver for the method call.
                                        let delegateType = sema.types.anyType
                                        let tempFieldRef = arena.appendExpr(.symbolRef(storageSym), type: delegateType)
                                        body.append(.copy(from: delegateValue, to: tempFieldRef))

                                        let propertyName = sema.symbols.symbol(propSymbol)?.name ?? compilationCtx.interner.intern("")
                                        let thisRefExprID: KIRExprID
                                        if let receiver = ctx.currentImplicitReceiverExprID {
                                            thisRefExprID = receiver
                                        } else {
                                            thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                                            body.append(.constValue(result: thisRefExprID, value: .null))
                                        }
                                        let kPropertyExprID = arena.appendExpr(
                                            .stringLiteral(propertyName),
                                            type: sema.types.make(.primitive(.string, .nonNull))
                                        )
                                        body.append(.constValue(result: kPropertyExprID, value: .stringLiteral(propertyName)))
                                        let provideDelegateResult = arena.appendExpr(
                                            .temporary(Int32(arena.expressions.count)),
                                            type: sema.types.anyType
                                        )
                                        // Emit as method call on the delegate storage
                                        // (2 args: thisRef, kProperty) matching Kotlin's
                                        // delegate.provideDelegate(thisRef, property).
                                        body.append(
                                            .call(
                                                symbol: storageSym,
                                                callee: provideDelegateName,
                                                arguments: [thisRefExprID, kPropertyExprID],
                                                result: provideDelegateResult,
                                                canThrow: false,
                                                thrownResult: nil
                                            )
                                        )
                                        valueToStore = provideDelegateResult
                                    } else {
                                        // No provideDelegate — store the delegate
                                        // expression value directly.
                                        valueToStore = delegateValue
                                    }

                                    if let storageSym = delegateStorageSym {
                                        let delegateType = sema.types.anyType
                                        let fieldRef = arena.appendExpr(.symbolRef(storageSym), type: delegateType)
                                        body.append(.copy(from: valueToStore, to: fieldRef))
                                    }
                                    continue
                                }

                                guard let initExpr = prop.initializer else {
                                    continue
                                }
                                let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
                                let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
                                let initValue = lowerExpr(
                                    initExpr,
                                    ast: ast,
                                    sema: sema,
                                    arena: arena,
                                    interner: compilationCtx.interner,
                                    propertyConstantInitializers: propertyConstantInitializers,
                                    instructions: &body
                                )
                                let fieldRef = arena.appendExpr(.symbolRef(targetSymbol), type: propType)
                                body.append(.copy(from: initValue, to: fieldRef))
                            }

                            for initBlock in classDecl.initBlocks {
                                switch initBlock {
                                case .block(let exprIDs, _):
                                    for exprID in exprIDs {
                                        _ = lowerExpr(
                                            exprID,
                                            ast: ast,
                                            sema: sema,
                                            arena: arena,
                                            interner: compilationCtx.interner,
                                            propertyConstantInitializers: propertyConstantInitializers,
                                            instructions: &body
                                        )
                                    }
                                case .expr(let exprID, _):
                                    _ = lowerExpr(
                                        exprID,
                                        ast: ast,
                                        sema: sema,
                                        arena: arena,
                                        interner: compilationCtx.interner,
                                        propertyConstantInitializers: propertyConstantInitializers,
                                        instructions: &body
                                    )
                                case .unit:
                                    break
                                }
                            }
                        }

                        if isSecondary {
                            for secondaryCtor in classDecl.secondaryConstructors {
                                guard secondaryCtor.range == sema.symbols.symbol(ctorSymbol)?.declSite else {
                                    continue
                                }
                                if let delegation = secondaryCtor.delegationCall {
                                    let delegationTarget: [InternedString]
                                    switch delegation.kind {
                                    case .this:
                                        delegationTarget = ctorFQName
                                    case .super_:
                                        let supertypes = sema.symbols.directSupertypes(for: symbol)
                                        let classSupertypes = supertypes.filter {
                                            let kind = sema.symbols.symbol($0)?.kind
                                            return kind == .class || kind == .enumClass
                                        }
                                        if let superclass = classSupertypes.first {
                                            delegationTarget = (sema.symbols.symbol(superclass)?.fqName ?? []) + [compilationCtx.interner.intern("<init>")]
                                        } else {
                                            delegationTarget = []
                                        }
                                    }
                                    if !delegationTarget.isEmpty {
                                        var argIDs: [KIRExprID] = []
                                        if let receiver = ctx.currentImplicitReceiverExprID {
                                            argIDs.append(receiver)
                                        }
                                        for arg in delegation.args {
                                            let lowered = lowerExpr(
                                                arg.expr,
                                                ast: ast,
                                                sema: sema,
                                                arena: arena,
                                                interner: compilationCtx.interner,
                                                propertyConstantInitializers: propertyConstantInitializers,
                                                instructions: &body
                                            )
                                            argIDs.append(lowered)
                                        }
                                        let delegationResultID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.unitType)
                                        body.append(.call(
                                            symbol: sema.symbols.lookupAll(fqName: delegationTarget).first,
                                            callee: compilationCtx.interner.intern("<init>"),
                                            arguments: argIDs,
                                            result: delegationResultID,
                                            canThrow: false,
                                            thrownResult: nil
                                        ))
                                    }
                                }
                                switch secondaryCtor.body {
                                case .block(let exprIDs, _):
                                    for exprID in exprIDs {
                                        _ = lowerExpr(
                                            exprID,
                                            ast: ast,
                                            sema: sema,
                                            arena: arena,
                                            interner: compilationCtx.interner,
                                            propertyConstantInitializers: propertyConstantInitializers,
                                            instructions: &body
                                        )
                                    }
                                case .expr(let exprID, _):
                                    _ = lowerExpr(
                                        exprID,
                                        ast: ast,
                                        sema: sema,
                                        arena: arena,
                                        interner: compilationCtx.interner,
                                        propertyConstantInitializers: propertyConstantInitializers,
                                        instructions: &body
                                    )
                                case .unit:
                                    break
                                }
                                break
                            }
                        }

                        if let receiver = ctx.currentImplicitReceiverExprID {
                            body.append(.returnValue(receiver))
                        } else {
                            body.append(.returnUnit)
                        }
                        body.append(.endBlock)

                        let ctorKirID = arena.appendDecl(
                            .function(
                                KIRFunction(
                                    symbol: ctorSymbol,
                                    name: classDecl.name,
                                    params: params,
                                    returnType: returnType,
                                    body: body,
                                    isSuspend: false,
                                    isInline: false
                                )
                            )
                        )
                        declIDs.append(ctorKirID)
                        // Generate default argument stub for constructors with defaults.
                        if let defaults = ctx.functionDefaultArgumentsBySymbol[ctorSymbol] {
                            let stubID = callSupportLowerer.generateDefaultStubFunction(
                                originalSymbol: ctorSymbol,
                                originalName: classDecl.name,
                                signature: signature,
                                defaultExpressions: defaults,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: compilationCtx.interner,
                                propertyConstantInitializers: propertyConstantInitializers
                            )
                            declIDs.append(stubID)
                        }
                        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
                    }

                case .interfaceDecl(let interfaceDecl):
                    // Interface properties have no backing storage; pass empty list.
                    var ifaceNestedObjects = interfaceDecl.nestedObjects
                    if let companionDeclID = interfaceDecl.companionObject {
                        ifaceNestedObjects.append(companionDeclID)
                    }
                    let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
                        memberFunctions: interfaceDecl.memberFunctions,
                        memberProperties: [],
                        nestedClasses: interfaceDecl.nestedClasses,
                        nestedObjects: ifaceNestedObjects,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: compilationCtx.interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)

                case .objectDecl(let objectDecl):
                    let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
                        memberFunctions: objectDecl.memberFunctions,
                        memberProperties: objectDecl.memberProperties,
                        nestedClasses: objectDecl.nestedClasses,
                        nestedObjects: objectDecl.nestedObjects,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: compilationCtx.interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
                    declIDs.append(kirID)
                    declIDs.append(contentsOf: allDecls)

                case .funDecl(let function):
                    ctx.resetScopeForFunction()
                    ctx.beginCallableLoweringScope()
                    let signature = sema.symbols.functionSignature(for: symbol)
                    var params: [KIRParameter] = []
                    if let signature {
                        if let receiverType = signature.receiverType {
                            let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol)
                            params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                            ctx.currentImplicitReceiverSymbol = receiverSymbol
                            ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
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
                            let tokenSymbol = SymbolID(rawValue: -20_000 - typeParamSymbol.rawValue)
                            params.append(KIRParameter(symbol: tokenSymbol, type: intType))
                        }
                    }
                    let returnType = signature?.returnType ?? sema.types.unitType
                    var body: [KIRInstruction] = [.beginBlock]
                    if let receiverExpr = ctx.currentImplicitReceiverExprID,
                       let receiverSymbol = ctx.currentImplicitReceiverSymbol {
                        body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
                    }
                    switch function.body {
                    case .block(let exprIDs, _):
                        var lastValue: KIRExprID?
                        var terminatedByReturn = false
                        for exprID in exprIDs {
                            if let expr = ast.arena.expr(exprID),
                               case .returnExpr(let value, _) = expr {
                                if let value {
                                    let lowered = lowerExpr(
                                        value,
                                        ast: ast,
                                        sema: sema,
                                        arena: arena,
                                        interner: compilationCtx.interner,
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
                            if let expr = ast.arena.expr(exprID),
                               case .throwExpr = expr {
                                _ = lowerExpr(
                                    exprID,
                                    ast: ast,
                                    sema: sema,
                                    arena: arena,
                                    interner: compilationCtx.interner,
                                    propertyConstantInitializers: propertyConstantInitializers,
                                    instructions: &body
                                )
                                terminatedByReturn = true
                                break
                            }
                            lastValue = lowerExpr(
                                exprID,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: compilationCtx.interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &body
                            )
                            // Detect nested termination (e.g., if/when/try with return in all branches)
                            if let lastValue, controlFlowLowerer.isTerminatedExpr(lastValue, arena: arena, sema: sema) {
                                terminatedByReturn = true
                                break
                            }
                        }
                        if !terminatedByReturn {
                            if let lastValue {
                                body.append(.returnValue(lastValue))
                            } else {
                                body.append(.returnUnit)
                            }
                        }
                    case .expr(let exprID, _):
                        let value = lowerExpr(
                            exprID,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: compilationCtx.interner,
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
                                isInline: function.isInline,
                                sourceRange: function.range
                            )
                        )
                    )
                    declIDs.append(kirID)
                    if let defaults = ctx.functionDefaultArgumentsBySymbol[symbol],
                       let sig = signature {
                        let stubID = callSupportLowerer.generateDefaultStubFunction(
                            originalSymbol: symbol,
                            originalName: function.name,
                            signature: sig,
                            defaultExpressions: defaults,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: compilationCtx.interner,
                            propertyConstantInitializers: propertyConstantInitializers
                        )
                        declIDs.append(stubID)
                    }
                    declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
                    ctx.currentImplicitReceiverExprID = nil
                    ctx.currentImplicitReceiverSymbol = nil

                case .propertyDecl(let propertyDecl):
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propType)))
                    declIDs.append(kirID)

                    // Emit backing field global for properties with custom accessors.
                    if let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) {
                        let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol) ?? propType
                        let backingFieldKirID = arena.appendDecl(
                            .global(KIRGlobal(symbol: backingFieldSymbol, type: backingFieldType))
                        )
                        declIDs.append(backingFieldKirID)
                    }

                    // Lower getter body as a KIR accessor function (top-level property).
                    if let getter = propertyDecl.getter, getter.body != .unit {
                        memberLowerer.lowerAccessorBody(
                            accessorBody: getter.body,
                            propertySymbol: symbol,
                            propertyType: propType,
                            accessorKind: .getter,
                            setterParamName: nil,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: compilationCtx.interner,
                            propertyConstantInitializers: propertyConstantInitializers,
                            allDecls: &declIDs
                        )
                    }

                    // Lower setter body as a KIR accessor function (top-level property).
                    if let setter = propertyDecl.setter, setter.body != .unit {
                        memberLowerer.lowerAccessorBody(
                            accessorBody: setter.body,
                            propertySymbol: symbol,
                            propertyType: propType,
                            accessorKind: .setter,
                            setterParamName: setter.parameterName,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: compilationCtx.interner,
                            propertyConstantInitializers: propertyConstantInitializers,
                            allDecls: &declIDs
                        )
                    }

                    // Collect top-level property initialization instructions
                    // (declaration order is preserved since we iterate topLevelDecls in order).
                    if let initializer = propertyDecl.initializer,
                       propertyDecl.delegateExpression == nil {
                        // Emit runtime init when the property is NOT a compile-time
                        // constant, OR when it is mutable (var).  Mutable properties
                        // are never constant-folded at use-sites (ExprLowerer skips
                        // inlining for .mutable), so their globals must be initialised
                        // to the declared value at program start.
                        if propertyConstantInitializers[symbol] == nil
                            || (sema.symbols.symbol(symbol)?.flags.contains(.mutable) == true) {
                            ctx.resetScopeForFunction()
                            ctx.beginCallableLoweringScope()
                            var initInstructions: [KIRInstruction] = []
                            let initValue = lowerExpr(
                                initializer,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: compilationCtx.interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &initInstructions
                            )
                            let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
                            initInstructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
                            initInstructions.append(.copy(from: initValue, to: globalRef))
                            allTopLevelInitInstructions.append(contentsOf: initInstructions)
                            declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
                        }
                    }

                    // Create delegate initialization and track the copy-target expr ID.
                    if propertyDecl.delegateExpression != nil {
                        let interner = compilationCtx.interner
                        let delegateType = sema.types.anyType
                        // Pre-allocate the copy-target expr ID that will hold the delegate handle.
                        // This expr ID will be the target of a `copy` instruction, which the LLVM
                        // backend maps to an alloca. We use this same expr ID as the argument in
                        // getValue calls so the backend loads from the alloca correctly.
                        let delegateHandleExpr = arena.appendExpr(.temporary(0), type: delegateType)
                        delegateHandleExprByPropertySymbol[symbol] = delegateHandleExpr

                        // Determine delegate kind and emit kk_*_create call.
                        let delegateKind = detectDelegateKind(
                            delegateExpr: propertyDecl.delegateExpression,
                            ast: ast,
                            interner: interner
                        )

                        ctx.resetScopeForFunction()
                        ctx.beginCallableLoweringScope()
                        var initInstructions: [KIRInstruction] = []

                        switch delegateKind {
                        case .lazy:
                            // Create lambda function from delegate body.
                            let lambdaFnPtr = lowerDelegateLambdaBody(
                                delegateBody: propertyDecl.delegateBody,
                                propertySymbol: symbol,
                                paramCount: 0,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &initInstructions
                            )
                            // Emit thread safety mode constant.
                            let modeValue = Int64(compilationCtx.options.lazyThreadSafetyMode.rawValue)
                            let modeExpr = arena.appendExpr(.intLiteral(modeValue), type: sema.types.anyType)
                            initInstructions.append(.constValue(result: modeExpr, value: .intLiteral(modeValue)))
                            // Emit kk_lazy_create(lambdaFnPtr, mode).
                            let createResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)), type: delegateType
                            )
                            let lazyCreateName = interner.intern("kk_lazy_create")
                            initInstructions.append(.call(
                                symbol: nil,
                                callee: lazyCreateName,
                                arguments: [lambdaFnPtr, modeExpr],
                                result: createResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            // Copy into delegateHandleExpr — the LLVM backend creates an alloca for copy targets.
                            initInstructions.append(.copy(from: createResult, to: delegateHandleExpr))

                        case .observable:
                            // Lower the initial value argument from the delegate expression.
                            let initialValueExpr = lowerDelegateInitialValue(
                                delegateExpr: propertyDecl.delegateExpression,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &initInstructions
                            )
                            // Create callback lambda from delegate body (3 params: prop, old, new).
                            let callbackFnPtr = lowerDelegateLambdaBody(
                                delegateBody: propertyDecl.delegateBody,
                                propertySymbol: symbol,
                                paramCount: 3,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &initInstructions
                            )
                            // Emit kk_observable_create(initialValue, callbackFnPtr).
                            let createResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)), type: delegateType
                            )
                            let observableCreateName = interner.intern("kk_observable_create")
                            initInstructions.append(.call(
                                symbol: nil,
                                callee: observableCreateName,
                                arguments: [initialValueExpr, callbackFnPtr],
                                result: createResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            // Copy into delegateHandleExpr — the LLVM backend creates an alloca for copy targets.
                            initInstructions.append(.copy(from: createResult, to: delegateHandleExpr))

                        case .vetoable:
                            // Lower the initial value argument from the delegate expression.
                            let initialValueExpr = lowerDelegateInitialValue(
                                delegateExpr: propertyDecl.delegateExpression,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &initInstructions
                            )
                            // Create callback lambda from delegate body (3 params: prop, old, new).
                            let callbackFnPtr = lowerDelegateLambdaBody(
                                delegateBody: propertyDecl.delegateBody,
                                propertySymbol: symbol,
                                paramCount: 3,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &initInstructions
                            )
                            // Emit kk_vetoable_create(initialValue, callbackFnPtr).
                            let createResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)), type: delegateType
                            )
                            let vetoableCreateName = interner.intern("kk_vetoable_create")
                            initInstructions.append(.call(
                                symbol: nil,
                                callee: vetoableCreateName,
                                arguments: [initialValueExpr, callbackFnPtr],
                                result: createResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            // Copy into delegateHandleExpr — the LLVM backend creates an alloca for copy targets.
                            initInstructions.append(.copy(from: createResult, to: delegateHandleExpr))

                        case .custom:
                            // Custom delegate: lower the full delegate expression as the
                            // delegate object and store it directly. The runtime's
                            // getValue/setValue will be called through
                            // kk_property_access at use-sites.
                            let delegateObjExpr = lowerExpr(
                                propertyDecl.delegateExpression!,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &initInstructions
                            )
                            // Emit kk_custom_delegate_create(delegateObj) to wrap the
                            // delegate into the standard handle format.
                            let createResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)), type: delegateType
                            )
                            let customCreateName = interner.intern("kk_custom_delegate_create")
                            initInstructions.append(.call(
                                symbol: nil,
                                callee: customCreateName,
                                arguments: [delegateObjExpr],
                                result: createResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            initInstructions.append(.copy(from: createResult, to: delegateHandleExpr))
                        }

                        allTopLevelInitInstructions.append(contentsOf: initInstructions)
                        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
                    }

                case .typeAliasDecl:
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                    declIDs.append(kirID)

                case .enumEntryDecl:
                    let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: sema.types.anyType)))
                    declIDs.append(kirID)
                }
            }
            files.append(KIRFile(fileID: file.fileID, decls: declIDs))
        }

        // Post-process: inject top-level property init and delegate init instructions
        // at the start of main, and rewrite delegate property accesses to getValue calls.
        if !allTopLevelInitInstructions.isEmpty || !delegateHandleExprByPropertySymbol.isEmpty {
            let interner = compilationCtx.interner
            let mainName = interner.intern("main")
            let lazyGetValueName = interner.intern("kk_lazy_get_value")
            let observableGetValueName = interner.intern("kk_observable_get_value")
            let vetoableGetValueName = interner.intern("kk_vetoable_get_value")
            let customGetValueName = interner.intern("kk_custom_delegate_get_value")

            // Build a reverse lookup: property symbol → delegate kind for getValue rewriting.
            var delegateKindByPropertySymbol: [SymbolID: StdlibDelegateKind] = [:]
            for file in ast.sortedFiles {
                for declID in file.topLevelDecls {
                    guard let decl = ast.arena.decl(declID),
                          case .propertyDecl(let prop) = decl,
                          let sym = sema.bindings.declSymbols[declID],
                          prop.delegateExpression != nil else {
                        continue
                    }
                    delegateKindByPropertySymbol[sym] = detectDelegateKind(
                        delegateExpr: prop.delegateExpression,
                        ast: ast,
                        interner: interner
                    )
                }
            }

            arena.transformFunctions { function in
                var updated = function
                // Inject all top-level property init instructions at the beginning of main function.
                // Instructions are already in declaration order (regular and delegate interleaved).
                if function.name == mainName, !allTopLevelInitInstructions.isEmpty {
                    var newBody: [KIRInstruction] = []
                    // Keep .beginBlock at the front if present.
                    if let first = function.body.first, case .beginBlock = first {
                        newBody.append(first)
                        newBody.append(contentsOf: allTopLevelInitInstructions)
                        newBody.append(contentsOf: function.body.dropFirst())
                    } else {
                        newBody.append(contentsOf: allTopLevelInitInstructions)
                        newBody.append(contentsOf: function.body)
                    }
                    updated.body = newBody
                }

                // Rewrite symbolRef accesses to delegate properties → getValue calls.
                // Instead of using symbolRef (which the LLVM C API backend can't resolve
                // for non-function/non-parameter symbols), we pass the copy-target expr ID
                // directly. The backend resolves copy targets via alloca/load.
                if !delegateHandleExprByPropertySymbol.isEmpty {
                    var rewrittenBody: [KIRInstruction] = []
                    rewrittenBody.reserveCapacity(updated.body.count)
                    for instruction in updated.body {
                        // Rewrite loadGlobal for delegate properties → getValue calls.
                        if case .loadGlobal(let result, let sym) = instruction,
                           let handleExpr = delegateHandleExprByPropertySymbol[sym] {
                            let getValueName: InternedString
                            switch delegateKindByPropertySymbol[sym] {
                            case .lazy:
                                getValueName = lazyGetValueName
                            case .observable:
                                getValueName = observableGetValueName
                            case .vetoable:
                                getValueName = vetoableGetValueName
                            case .custom:
                                getValueName = customGetValueName
                            case nil:
                                getValueName = customGetValueName
                            }
                            rewrittenBody.append(
                                .call(
                                    symbol: nil,
                                    callee: getValueName,
                                    arguments: [handleExpr],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }
                        if case .constValue(let result, let value) = instruction,
                           case .symbolRef(let sym) = value,
                           let handleExpr = delegateHandleExprByPropertySymbol[sym] {
                            // Replace raw symbolRef with a getValue call, passing the
                            // copy-target (alloca) that holds the delegate handle.
                            let getValueName: InternedString
                            switch delegateKindByPropertySymbol[sym] {
                            case .lazy:
                                getValueName = lazyGetValueName
                            case .observable:
                                getValueName = observableGetValueName
                            case .vetoable:
                                getValueName = vetoableGetValueName
                            case .custom:
                                getValueName = customGetValueName
                            case nil:
                                getValueName = customGetValueName
                            }
                            rewrittenBody.append(
                                .call(
                                    symbol: nil,
                                    callee: getValueName,
                                    arguments: [handleExpr],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }
                        rewrittenBody.append(instruction)
                    }
                    updated.body = rewrittenBody
                }

                return updated
            }
        }

        return KIRModule(files: files, arena: arena)
    }

    // MARK: - Delegate Lowering Helpers

    /// Detects the delegate kind from the delegate expression AST node.
    private func detectDelegateKind(
        delegateExpr: ExprID?,
        ast: ASTModule,
        interner: StringInterner
    ) -> StdlibDelegateKind {
        guard let exprID = delegateExpr,
              let expr = ast.arena.expr(exprID) else {
            return .custom
        }
        switch expr {
        case .nameRef(let name, _):
            let resolved = interner.resolve(name)
            if resolved == "lazy" { return .lazy }
            return .custom
        case .call(let callee, _, _, _):
            // call(callee: memberCall(...) or nameRef(...))
            if let calleeExpr = ast.arena.expr(callee) {
                switch calleeExpr {
                case .nameRef(let name, _):
                    let resolved = interner.resolve(name)
                    if resolved == "observable" { return .observable }
                    if resolved == "vetoable" { return .vetoable }
                    if resolved == "lazy" { return .lazy }
                default:
                    break
                }
            }
            // Check memberCall pattern: Delegates.observable(...)
            return detectDelegateKindFromCallExpr(callee: callee, ast: ast, interner: interner)
        case .memberCall(_, let callee, _, _, _):
            let resolved = interner.resolve(callee)
            if resolved == "observable" { return .observable }
            if resolved == "vetoable" { return .vetoable }
            return .custom
        default:
            return .custom
        }
    }

    private func detectDelegateKindFromCallExpr(
        callee: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> StdlibDelegateKind {
        guard let expr = ast.arena.expr(callee) else { return .custom }
        // memberAccess: Delegates.observable → memberCall with receiver
        // In the expression parser, `Delegates.observable("initial")` may be parsed as
        // call(callee: memberAccess(...), args: [...])
        // We need to check if the callee resolves to "observable" or "vetoable".
        switch expr {
        case .memberCall(_, let name, _, _, _):
            let resolved = interner.resolve(name)
            if resolved == "observable" { return .observable }
            if resolved == "vetoable" { return .vetoable }
        case .nameRef(let name, _):
            let resolved = interner.resolve(name)
            if resolved == "observable" { return .observable }
            if resolved == "vetoable" { return .vetoable }
        default:
            break
        }
        return .custom
    }

    /// Creates a lambda function from the delegate body and returns a KIR expression
    /// referencing the lambda's symbol (function pointer).
    private func lowerDelegateLambdaBody(
        delegateBody: FunctionBody?,
        propertySymbol: SymbolID,
        paramCount: Int,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let lambdaSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let lambdaName = interner.intern("kk_delegate_lambda_\(propertySymbol.rawValue)")

        // Create parameters for the lambda.
        var params: [KIRParameter] = []
        for i in 0..<paramCount {
            let paramSymbol = SymbolID(rawValue: -(propertySymbol.rawValue + Int32(i + 1) * 1000 + 50_000))
            params.append(KIRParameter(symbol: paramSymbol, type: sema.types.anyType))
        }

        var lambdaBody: [KIRInstruction] = [.beginBlock]
        // Bind parameter symbols so they're accessible in the body.
        for param in params {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            ctx.localValuesBySymbol[param.symbol] = paramExpr
        }

        // Lower the delegate body expressions.
        switch delegateBody {
        case .block(let exprIDs, _):
            var lastValue: KIRExprID?
            for exprID in exprIDs {
                lastValue = lowerExpr(
                    exprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &lambdaBody
                )
            }
            if let lastValue {
                lambdaBody.append(.returnValue(lastValue))
            } else {
                lambdaBody.append(.returnUnit)
            }
        case .expr(let exprID, _):
            let value = lowerExpr(
                exprID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &lambdaBody
            )
            lambdaBody.append(.returnValue(value))
        case .unit, nil:
            lambdaBody.append(.returnUnit)
        }
        lambdaBody.append(.endBlock)

        let returnType = sema.types.anyType
        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: params,
                    returnType: returnType,
                    body: lambdaBody,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        ctx.pendingGeneratedCallableDeclIDs.append(lambdaDecl)

        // Return a symbolRef expression pointing to the lambda function.
        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: sema.types.anyType)
        instructions.append(.constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)))
        return lambdaRefExpr
    }

    /// Lowers the initial value argument from a delegate expression
    /// (e.g., the `"initial"` in `Delegates.observable("initial")`).
    private func lowerDelegateInitialValue(
        delegateExpr: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let exprID = delegateExpr,
              let expr = ast.arena.expr(exprID) else {
            // Fallback: return 0.
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return zeroExpr
        }

        // For call expressions like `Delegates.observable("initial")` or `observable("initial")`,
        // extract and lower the first argument.
        switch expr {
        case .call(_, _, let args, _):
            if let firstArg = args.first {
                return lowerExpr(
                    firstArg.expr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
        case .memberCall(_, _, _, let args, _):
            if let firstArg = args.first {
                return lowerExpr(
                    firstArg.expr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
        default:
            break
        }

        // Fallback: lower the entire delegate expression as the initial value.
        return lowerExpr(
            exprID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }
}
