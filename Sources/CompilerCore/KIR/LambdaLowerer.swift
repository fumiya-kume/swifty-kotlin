import Foundation

struct KIRCallableValueInfo {
    let symbol: SymbolID
    let callee: InternedString
    let captureArguments: [KIRExprID]
    /// True when lambda has closure param for C HOF ABI (filter, map, etc.).
    let hasClosureParam: Bool
}

final class LambdaLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func lowerLambdaLiteralExpr(
        _ exprID: ExprID,
        params: [InternedString],
        bodyExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        // For SAM-converted lambdas, the bound type is the interface type.
        // Use the stored underlying function type instead.
        let effectiveFuncTypeID: TypeID? = {
            if sema.bindings.isSamConversion(exprID),
               let samFuncType = sema.bindings.samUnderlyingFunctionType(for: exprID)
            {
                return samFuncType
            }
            return boundType
        }()
        let functionType = effectiveFuncTypeID.flatMap { typeID -> FunctionType? in
            guard case let .functionType(functionType) = sema.types.kind(of: typeID) else {
                return nil
            }
            return functionType
        }

        let lambdaName = syntheticLambdaName(for: exprID, interner: interner)
        let isSamConversion = sema.bindings.isSamConversion(exprID)
        let lambdaSymbol: SymbolID = if isSamConversion {
            sema.symbols.define(
                kind: .function,
                name: lambdaName,
                fqName: [lambdaName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        } else {
            driver.ctx.syntheticLambdaSymbol(for: exprID)
        }

        // Effective parameter count: when the AST has zero explicit params but
        // the bound function type declares parameters (implicit `it`), use the
        // function-type parameter count so that the generated KIR function
        // receives the expected arguments.
        let effectiveParamCount: Int = if params.isEmpty, let functionType, !functionType.params.isEmpty {
            functionType.params.count
        } else {
            params.count
        }

        let lambdaParameterTypes: [TypeID] = (0 ..< effectiveParamCount).map { index in
            if let functionType, index < functionType.params.count {
                return functionType.params[index]
            }
            return sema.types.anyType
        }
        let lambdaReturnType = functionType?.returnType
            ?? sema.bindings.exprTypes[bodyExpr]
            ?? sema.types.anyType

        let captureSymbols = computeCaptureSymbolsForLambda(
            lambdaExprID: exprID,
            lambdaParamCount: effectiveParamCount,
            lambdaBodyExprID: bodyExpr,
            ast: ast,
            sema: sema
        )

        var captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID)] = []
        captureBindings.reserveCapacity(captureSymbols.count)
        for (index, symbol) in captureSymbols.enumerated() {
            guard let captureValueExpr = captureValueExpr(
                for: symbol,
                sema: sema,
                arena: arena,
                instructions: &instructions
            ) else {
                continue
            }
            let captureType = arena.exprType(captureValueExpr) ?? typeForSymbolReference(symbol, sema: sema)
            let captureParamSymbol = syntheticLambdaCaptureParamSymbol(
                lambdaExprID: exprID,
                captureIndex: index
            )
            let captureParam = KIRParameter(symbol: captureParamSymbol, type: captureType)
            captureBindings.append((
                capturedSymbol: symbol,
                param: captureParam,
                valueExpr: captureValueExpr
            ))
        }

        // For lambdas passed to C HOFs (filter, map, mapIndexed, forEachIndexed, fold, etc.),
        // Runtime expects (closureRaw, ...valueParams, outThrown). Add closure param as first param.
        let lambdaParameters: [KIRParameter]
        let needsClosureParam = sema.bindings.isCollectionHOFLambdaExpr(exprID) && !isSamConversion
        if needsClosureParam, effectiveParamCount == 0 {
            let closureParam = KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: sema.types.intType
            )
            lambdaParameters = [closureParam]
        } else if needsClosureParam, effectiveParamCount == 1 {
            let closureParam = KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: sema.types.intType
            )
            let elemParam = KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 0),
                type: lambdaParameterTypes[0]
            )
            lambdaParameters = [closureParam, elemParam]
        } else if needsClosureParam, effectiveParamCount == 2 {
            // mapIndexed/forEachIndexed/fold/reduce: (closureRaw, param0, param1, outThrown)
            let closureParam = KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: sema.types.intType
            )
            let param0 = KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 0),
                type: lambdaParameterTypes[0]
            )
            let param1 = KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 1),
                type: lambdaParameterTypes[1]
            )
            lambdaParameters = [closureParam, param0, param1]
        } else {
            lambdaParameters = (0 ..< effectiveParamCount).map { index in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: lambdaParameterTypes[index]
                )
            }
        }
        let usesClosureRawCapture = needsClosureParam && captureBindings.count == 1
        let functionCaptureBindings = usesClosureRawCapture ? [] : captureBindings

        let scopeSnapshot = driver.ctx.saveScope()
        let savedReceiverSymbol = scopeSnapshot.currentImplicitReceiverSymbol
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()

        var lambdaBody: [KIRInstruction] = [.beginBlock]
        for capture in functionCaptureBindings {
            let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
            lambdaBody.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
            driver.ctx.localValuesBySymbol[capture.capturedSymbol] = captureExpr
            if capture.capturedSymbol == savedReceiverSymbol {
                driver.ctx.currentImplicitReceiverExprID = captureExpr
                driver.ctx.currentImplicitReceiverSymbol = capture.param.symbol
            }
        }
        for lambdaParam in lambdaParameters {
            let paramExpr = arena.appendExpr(.symbolRef(lambdaParam.symbol), type: lambdaParam.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(lambdaParam.symbol)))
            driver.ctx.localValuesBySymbol[lambdaParam.symbol] = paramExpr
        }
        if usesClosureRawCapture,
           let closureCapture = captureBindings.first,
           let closureParam = lambdaParameters.first,
           let closureExpr = driver.ctx.localValuesBySymbol[closureParam.symbol]
        {
            driver.ctx.localValuesBySymbol[closureCapture.capturedSymbol] = closureExpr
            if closureCapture.capturedSymbol == savedReceiverSymbol {
                driver.ctx.currentImplicitReceiverExprID = closureExpr
                driver.ctx.currentImplicitReceiverSymbol = closureParam.symbol
            }
        }
        // Map param names → symbols for nameRef fallback when identifierSymbols is unbound.
        let effectiveParamNames: [InternedString] = if params.isEmpty, let functionType, !functionType.params.isEmpty {
            [interner.intern("it")]
        } else {
            params
        }
        let valueParamStart = needsClosureParam ? 1 : 0
        for (i, paramName) in effectiveParamNames.enumerated() where valueParamStart + i < lambdaParameters.count {
            driver.ctx.lambdaParamNameToSymbol[paramName] = lambdaParameters[valueParamStart + i].symbol
        }

        let loweredBody = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &lambdaBody
        )
        lambdaBody.append(.returnValue(loweredBody))
        lambdaBody.append(.endBlock)

        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: functionCaptureBindings.map(\.param) + lambdaParameters,
                    returnType: lambdaReturnType,
                    body: lambdaBody,
                    isSuspend: functionType?.isSuspend ?? false,
                    isInline: false
                )
            )
        )
        driver.ctx.pendingGeneratedCallableDeclIDs.append(lambdaDecl)

        if isSamConversion,
           let boundType,
           case let .classType(interfaceType) = sema.types.kind(of: boundType),
           let samValue = lowerSamWrapperValue(
               exprID,
               interfaceSymbol: interfaceType.classSymbol,
               lambdaSymbol: lambdaSymbol,
               lambdaName: lambdaName,
               lambdaReturnType: lambdaReturnType,
               captureBindings: captureBindings,
               samMethodParamTypes: lambdaParameterTypes,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return samValue
        }

        // For SAM-converted lambdas, use the function type (not the interface
        // type) so the KIR callable value machinery dispatches correctly.
        let lambdaValueType = effectiveFuncTypeID
            ?? boundType
            ?? sema.types.make(
                .functionType(
                    FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType,
                        isSuspend: functionType?.isSuspend ?? false,
                        nullability: .nonNull
                    )
                )
            )
        let lambdaValueExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: lambdaValueType)
        instructions.append(.constValue(result: lambdaValueExpr, value: .symbolRef(lambdaSymbol)))
        driver.ctx.registerCallableValue(
            lambdaValueExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: usesClosureRawCapture ? captureBindings.map(\.valueExpr) : functionCaptureBindings.map(\.valueExpr),
            hasClosureParam: needsClosureParam
        )
        return lambdaValueExpr
    }

    private func lowerSamWrapperValue(
        _ exprID: ExprID,
        interfaceSymbol: SymbolID,
        lambdaSymbol: SymbolID,
        lambdaName: InternedString,
        lambdaReturnType: TypeID,
        captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID)],
        samMethodParamTypes: [TypeID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
              interfaceInfo.kind == .interface,
              interfaceInfo.flags.contains(.funInterface),
              let samMethod = samMethodSymbolAndSignature(for: interfaceSymbol, sema: sema)
        else {
            return nil
        }

        let wrapperName = interner.intern("kk_sam_wrapper_\(exprID.rawValue)")
        let wrapperFQName = [wrapperName]
        let wrapperSymbol = sema.symbols.define(
            kind: .class,
            name: wrapperName,
            fqName: wrapperFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.symbols.setDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
        sema.types.setNominalDirectSupertypes([interfaceSymbol], for: wrapperSymbol)

        let wrapperType = sema.types.make(.classType(ClassType(
            classSymbol: wrapperSymbol,
            args: [],
            nullability: .nonNull
        )))

        var fieldOffsets: [SymbolID: Int] = [:]
        var nextFieldOffset = 2
        let captureFieldSymbols = captureBindings.enumerated().map { index, capture in
            let fieldName = interner.intern("$sam_capture_\(index)")
            let fieldSymbol = sema.symbols.define(
                kind: .field,
                name: fieldName,
                fqName: wrapperFQName + [fieldName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setParentSymbol(wrapperSymbol, for: fieldSymbol)
            sema.symbols.setPropertyType(capture.param.type, for: fieldSymbol)
            fieldOffsets[fieldSymbol] = nextFieldOffset
            nextFieldOffset += 1
            return fieldSymbol
        }

        let methodName = samMethod.info.name
        let methodSymbol = sema.symbols.define(
            kind: .function,
            name: methodName,
            fqName: wrapperFQName + [methodName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        sema.symbols.setParentSymbol(wrapperSymbol, for: methodSymbol)

        let methodParamSymbols: [SymbolID] = samMethod.signature.parameterTypes.enumerated().map { index, type in
            let paramName = interner.intern("$p\(index)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: wrapperFQName + [methodName, paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setPropertyType(type, for: paramSymbol)
            return paramSymbol
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: wrapperType,
                parameterTypes: samMethod.signature.parameterTypes,
                returnType: samMethod.signature.returnType,
                isSuspend: samMethod.signature.isSuspend,
                valueParameterSymbols: methodParamSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: methodParamSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: methodParamSymbols.count),
                typeParameterSymbols: []
            ),
            for: methodSymbol
        )
        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: captureFieldSymbols.count,
                instanceSizeWords: max(2 + captureFieldSymbols.count, 1),
                fieldOffsets: fieldOffsets,
                vtableSlots: [methodSymbol: 0, samMethod.symbol: 0],
                itableSlots: [interfaceSymbol: 0],
                vtableSize: 1,
                superClass: nil
            ),
            for: wrapperSymbol
        )

        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: wrapperSymbol)))
        driver.ctx.pendingGeneratedCallableDeclIDs.append(nominalDeclID)

        let scopeSnapshot = driver.ctx.saveScope()
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()
        driver.ctx.currentFunctionSymbol = methodSymbol

        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        driver.ctx.currentImplicitReceiverSymbol = receiverSymbol
        driver.ctx.currentImplicitReceiverExprID = receiverExpr

        let methodParams = [KIRParameter(symbol: receiverSymbol, type: wrapperType)]
            + zip(methodParamSymbols, samMethod.signature.parameterTypes).map { KIRParameter(symbol: $0.0, type: $0.1) }
        var methodBody: [KIRInstruction] = [.beginBlock]
        methodBody.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))

        var loadedCaptureExprs: [KIRExprID] = []
        for (index, fieldSymbol) in captureFieldSymbols.enumerated() {
            guard let fieldOffset = fieldOffsets[fieldSymbol] else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            methodBody.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let captureType = captureBindings[index].param.type
            let loadedExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: captureType)
            methodBody.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExpr, offsetExpr],
                result: loadedExpr,
                canThrow: false,
                thrownResult: nil
            ))
            loadedCaptureExprs.append(loadedExpr)
        }

        let loweredMethodParamExprs = zip(methodParamSymbols, samMethod.signature.parameterTypes).map { symbol, type in
            let expr = arena.appendExpr(.symbolRef(symbol), type: type)
            methodBody.append(.constValue(result: expr, value: .symbolRef(symbol)))
            return expr
        }

        let callResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: lambdaReturnType)
        methodBody.append(.call(
            symbol: lambdaSymbol,
            callee: lambdaName,
            arguments: loadedCaptureExprs + loweredMethodParamExprs,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        if samMethod.signature.returnType == sema.types.unitType {
            methodBody.append(.returnUnit)
        } else {
            methodBody.append(.returnValue(callResult))
        }
        methodBody.append(.endBlock)

        let methodDeclID = arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: methodName,
            params: methodParams,
            returnType: samMethod.signature.returnType,
            body: methodBody,
            isSuspend: samMethod.signature.isSuspend,
            isInline: false
        )))
        driver.ctx.pendingGeneratedCallableDeclIDs.append(methodDeclID)
        driver.ctx.restoreScope(scopeSnapshot)

        let slotCount = Int64(max(2 + captureFieldSymbols.count, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: sema.types.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: wrapperSymbol,
            sema: sema,
            interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: sema.types.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let wrapperValue = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: sema.types.make(.classType(ClassType(classSymbol: interfaceSymbol, args: [], nullability: .nonNull)))
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: wrapperValue,
            canThrow: false,
            thrownResult: nil
        ))

        let childTypeExpr = arena.appendExpr(.intLiteral(classIDValue), type: sema.types.intType)
        instructions.append(.constValue(result: childTypeExpr, value: .intLiteral(classIDValue)))
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: sema.types.intType)
        instructions.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
        let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_type_register_iface"),
            arguments: [childTypeExpr, interfaceTypeExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))

        let ifaceSlot = Int64(sema.symbols.nominalLayout(for: wrapperSymbol)?.itableSlots[interfaceSymbol] ?? 0)
        let methodSlot = Int64(sema.symbols.nominalLayout(for: interfaceSymbol)?.vtableSlots[samMethod.symbol] ?? 0)
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: sema.types.intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
        let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: sema.types.intType)
        instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
        let methodFnExpr = arena.appendExpr(.symbolRef(methodSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(methodSymbol)))
        let registerMethodResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_register_itable_method"),
            arguments: [wrapperValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
            result: registerMethodResult,
            canThrow: false,
            thrownResult: nil
        ))

        for (index, capture) in captureBindings.enumerated() {
            guard index < captureFieldSymbols.count,
                  let fieldOffset = fieldOffsets[captureFieldSymbols[index]]
            else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let unusedResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [wrapperValue, offsetExpr, capture.valueExpr],
                result: unusedResult,
                canThrow: true,
                thrownResult: nil
            ))
        }

        _ = samMethodParamTypes
        return wrapperValue
    }

    private func samMethodSymbolAndSignature(
        for interfaceSymbol: SymbolID,
        sema: SemaModule
    ) -> (symbol: SymbolID, info: SemanticSymbol, signature: FunctionSignature)? {
        guard let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
              interfaceInfo.kind == .interface,
              interfaceInfo.flags.contains(.funInterface)
        else {
            return nil
        }
        let abstractMethods = sema.symbols.children(ofFQName: interfaceInfo.fqName).compactMap { childID -> (SymbolID, SemanticSymbol, FunctionSignature)? in
            guard let childInfo = sema.symbols.symbol(childID),
                  childInfo.kind == .function,
                  childInfo.flags.contains(.abstractType),
                  let signature = sema.symbols.functionSignature(for: childID)
            else {
                return nil
            }
            return (childID, childInfo, signature)
        }
        guard abstractMethods.count == 1 else {
            return nil
        }
        return abstractMethods[0]
    }

    func lowerCallableRefExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID?,
        memberName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        var captureArguments: [KIRExprID] = []
        if let receiverExpr {
            let loweredReceiver = driver.lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            captureArguments.append(loweredReceiver)
        }

        let targetSymbol = resolveCallableRefTargetSymbol(
            exprID: exprID,
            receiverExpr: receiverExpr,
            memberName: memberName,
            sema: sema
        )

        let callableSymbol: SymbolID
        let callableName: InternedString
        if let targetSymbol {
            callableSymbol = targetSymbol
            callableName = callableTargetName(for: targetSymbol, sema: sema, interner: interner)
        } else {
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)
            let fallbackFunctionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(functionType) = sema.types.kind(of: typeID) else {
                    return nil
                }
                return functionType
            }
            let fallbackValueParamTypes = fallbackFunctionType?.params ?? []
            let fallbackReturnType = fallbackFunctionType?.returnType ?? sema.types.anyType

            let captureParams: [KIRParameter] = captureArguments.enumerated().map { index, captureExpr in
                KIRParameter(
                    symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: index),
                    type: arena.exprType(captureExpr) ?? sema.types.anyType
                )
            }
            let valueParams: [KIRParameter] = fallbackValueParamTypes.enumerated().map { index, type in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: type
                )
            }
            var body: [KIRInstruction] = [.beginBlock]
            switch sema.types.kind(of: fallbackReturnType) {
            case .unit, .nothing(.nonNull), .nothing(.nullable):
                body.append(.returnUnit)
            default:
                let zero = arena.appendExpr(.intLiteral(0), type: fallbackReturnType)
                body.append(.constValue(result: zero, value: .intLiteral(0)))
                body.append(.returnValue(zero))
            }
            body.append(.endBlock)

            let fallbackDecl = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: callableSymbol,
                        name: callableName,
                        params: captureParams + valueParams,
                        returnType: fallbackReturnType,
                        body: body,
                        isSuspend: fallbackFunctionType?.isSuspend ?? false,
                        isInline: false
                    )
                )
            )
            driver.ctx.pendingGeneratedCallableDeclIDs.append(fallbackDecl)
        }

        let callableType = boundType ?? typeForSymbolReference(callableSymbol, sema: sema)
        let callableExpr = arena.appendExpr(.symbolRef(callableSymbol), type: callableType)
        instructions.append(.constValue(result: callableExpr, value: .symbolRef(callableSymbol)))
        driver.ctx.registerCallableValue(
            callableExpr,
            symbol: callableSymbol,
            callee: callableName,
            captureArguments: captureArguments
        )
        return callableExpr
    }
}
