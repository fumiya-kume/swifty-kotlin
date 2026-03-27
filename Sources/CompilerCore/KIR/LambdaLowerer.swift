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

    private func normalizeHOFPrimitiveParameter(
        _ exprID: KIRExprID,
        type: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let unboxCallee: String? = switch sema.types.kind(of: type) {
        case .primitive(.int, .nonNull),
             .primitive(.uint, .nonNull), .primitive(.ushort, .nonNull), .primitive(.ubyte, .nonNull):
            "kk_unbox_int"
        case .primitive(.long, .nonNull), .primitive(.ulong, .nonNull):
            "kk_unbox_long"
        case .primitive(.boolean, .nonNull):
            "kk_unbox_bool"
        case .primitive(.char, .nonNull):
            "kk_unbox_char"
        case .primitive(.float, .nonNull):
            "kk_unbox_float"
        case .primitive(.double, .nonNull):
            "kk_unbox_double"
        default:
            nil
        }
        guard let unboxCallee else {
            return exprID
        }
        let normalizedExpr = arena.appendExpr(
            .temporary(Int32(clamping: arena.expressions.count)),
            type: type
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(unboxCallee),
            arguments: [exprID],
            result: normalizedExpr,
            canThrow: false,
            thrownResult: nil
        ))
        return normalizedExpr
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

        // Enhanced receiver parameter handling for lambda with receiver types
        let hasReceiverParam = functionType?.receiver != nil
        let effectiveParamCount: Int = {
            let baseCount: Int = if params.isEmpty, let functionType, !functionType.params.isEmpty {
                functionType.params.count
            } else {
                params.count
            }
            // For receiver lambdas (e.g., StringBuilder.() -> Unit), the receiver
            // is implicitly passed as the first parameter, but only if there's no
            // active implicit receiver in the current scope
            let needsExplicitReceiver = hasReceiverParam && driver.ctx.activeImplicitReceiverExprID() == nil
            return baseCount + (needsExplicitReceiver ? 1 : 0)
        }()

        let lambdaParameterTypes: [TypeID] = {
            var types: [TypeID] = []
            // Add receiver parameter first if needed
            let needsExplicitReceiver = hasReceiverParam && driver.ctx.activeImplicitReceiverExprID() == nil
            if needsExplicitReceiver, let receiverType = functionType?.receiver {
                types.append(receiverType)
            }
            let valueParamCount = effectiveParamCount - (needsExplicitReceiver ? 1 : 0)
            for index in 0 ..< valueParamCount {
                if let functionType, index < functionType.params.count {
                    types.append(functionType.params[index])
                } else {
                    types.append(sema.types.anyType)
                }
            }
            return types
        }()
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
        let needsClosureParam = sema.bindings.isCollectionHOFLambdaExpr(exprID) && !isSamConversion

        // Non-capturing lambda optimization: if no captures, use function pointer directly
        let isNonCapturingLambda = captureSymbols.isEmpty && !needsClosureParam
        if isNonCapturingLambda {
            return lowerNonCapturingLambda(
                exprID: exprID,
                params: params,
                bodyExpr: bodyExpr,
                effectiveParamCount: effectiveParamCount,
                lambdaParameterTypes: lambdaParameterTypes,
                lambdaReturnType: lambdaReturnType,
                functionType: functionType,
                isSamConversion: isSamConversion,
                boundType: boundType,
                effectiveFuncTypeID: effectiveFuncTypeID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        var captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID)] = []
        captureBindings.reserveCapacity(captureSymbols.count)
        for (index, symbol) in captureSymbols.enumerated() {
            let declaredType = driver.ctx.localDeclaredType(for: symbol) ?? typeForSymbolReference(symbol, sema: sema)
            guard let captureValueExpr = captureValueExpr(
                for: symbol,
                sema: sema,
                arena: arena,
                interner: interner,
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
                valueExpr: captureValueExpr,
                declaredType: declaredType
            ))
        }

        // For lambdas passed to C HOFs (filter, map, mapIndexed, forEachIndexed, fold, etc.),
        // Runtime expects (closureRaw, ...valueParams, outThrown). Add closure param as first param.
        let lambdaParameters: [KIRParameter]
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
        } else if needsClosureParam, effectiveParamCount == 3 {
            // foldIndexed/reduceIndexed/scanIndexed etc.: (closureRaw, param0, param1, param2, outThrown)
            let closureParam = KIRParameter(symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID), type: sema.types.intType)
            let param0 = KIRParameter(symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 0), type: lambdaParameterTypes[0])
            let param1 = KIRParameter(symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 1), type: lambdaParameterTypes[1])
            let param2 = KIRParameter(symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 2), type: lambdaParameterTypes[2])
            lambdaParameters = [closureParam, param0, param1, param2]
        } else {
            lambdaParameters = (0 ..< effectiveParamCount).map { index in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: lambdaParameterTypes[index]
                )
            }
        }
        let usesClosureRawCapture = needsClosureParam && captureBindings.count == 1
        let usesClosureObjectCapture = needsClosureParam && captureBindings.count >= 2
        let functionCaptureBindings = (usesClosureRawCapture || usesClosureObjectCapture) ? [] : captureBindings

        let scopeSnapshot = driver.ctx.saveScope()
        let savedReceiverSymbol = scopeSnapshot.currentImplicitReceiverSymbol
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()

        var lambdaBody: [KIRInstruction] = [.beginBlock]
        for capture in functionCaptureBindings {
            let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
            lambdaBody.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
            if let semanticSymbol = sema.symbols.symbol(capture.capturedSymbol),
               semanticSymbol.kind == .local,
               semanticSymbol.flags.contains(.mutable)
            {
                driver.ctx.setMutableCaptureCell(captureExpr, for: capture.capturedSymbol)
                driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.capturedSymbol)
            } else {
                driver.ctx.setLocalValue(captureExpr, for: capture.capturedSymbol)
                driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.capturedSymbol)
            }
            if capture.capturedSymbol == savedReceiverSymbol {
                driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: captureExpr)
            }
        }
        for (paramIndex, lambdaParam) in lambdaParameters.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(lambdaParam.symbol), type: lambdaParam.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(lambdaParam.symbol)))
            let normalizedParamExpr: KIRExprID
            if needsClosureParam, paramIndex > 0 {
                normalizedParamExpr = normalizeHOFPrimitiveParameter(
                    paramExpr,
                    type: lambdaParam.type,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &lambdaBody
                )
            } else {
                normalizedParamExpr = paramExpr
            }
            driver.ctx.setLocalValue(normalizedParamExpr, for: lambdaParam.symbol)
            // When the first parameter is the receiver (from a function-with-receiver type),
            // set it as the implicit receiver so that member calls resolve correctly.
            if paramIndex == 0, hasReceiverParam {
                driver.ctx.setImplicitReceiver(symbol: lambdaParam.symbol, exprID: normalizedParamExpr)
            }
        }
        if usesClosureRawCapture,
           let closureCapture = captureBindings.first,
           let closureParam = lambdaParameters.first,
           let closureExpr = driver.ctx.localValue(for: closureParam.symbol)
        {
            if let semanticSymbol = sema.symbols.symbol(closureCapture.capturedSymbol),
               semanticSymbol.kind == .local,
               semanticSymbol.flags.contains(.mutable)
            {
                driver.ctx.setMutableCaptureCell(closureExpr, for: closureCapture.capturedSymbol)
                driver.ctx.setLocalDeclaredType(closureCapture.declaredType, for: closureCapture.capturedSymbol)
            } else {
                driver.ctx.setLocalValue(closureExpr, for: closureCapture.capturedSymbol)
                driver.ctx.setLocalDeclaredType(closureCapture.declaredType, for: closureCapture.capturedSymbol)
            }
            if closureCapture.capturedSymbol == savedReceiverSymbol {
                driver.ctx.setImplicitReceiver(symbol: closureParam.symbol, exprID: closureExpr)
            }
        }
        // Multi-capture HOF lambda: closureRaw is a packed closure object.
        // Load each capture from the object via kk_array_get_inbounds.
        if usesClosureObjectCapture,
           let closureParam = lambdaParameters.first,
           let closureObjExpr = driver.ctx.localValue(for: closureParam.symbol)
        {
            let kkArrayGet = interner.intern("kk_array_get_inbounds")
            for (captureIndex, capture) in captureBindings.enumerated() {
                let fieldOffset = Int64(captureIndex + 2)
                let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: sema.types.intType)
                lambdaBody.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
                let loadedExpr = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: capture.param.type)
                lambdaBody.append(.call(
                    symbol: nil,
                    callee: kkArrayGet,
                    arguments: [closureObjExpr, offsetExpr],
                    result: loadedExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let semanticSymbol = sema.symbols.symbol(capture.capturedSymbol),
                   semanticSymbol.kind == .local,
                   semanticSymbol.flags.contains(.mutable)
                {
                    driver.ctx.setMutableCaptureCell(loadedExpr, for: capture.capturedSymbol)
                    driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.capturedSymbol)
                } else {
                    driver.ctx.setLocalValue(loadedExpr, for: capture.capturedSymbol)
                    driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.capturedSymbol)
                }
                if capture.capturedSymbol == savedReceiverSymbol {
                    driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: loadedExpr)
                }
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
            driver.ctx.registerLambdaParam(symbol: lambdaParameters[valueParamStart + i].symbol, forName: paramName)
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
        driver.ctx.appendGeneratedCallableDecl(lambdaDecl)

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
        let captureArgs = (usesClosureRawCapture || usesClosureObjectCapture) ? captureBindings.map(\.valueExpr) : functionCaptureBindings.map(\.valueExpr)
        driver.ctx.registerCallableValue(
            lambdaValueExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: captureArgs,
            hasClosureParam: needsClosureParam
        )
        if !captureArgs.isEmpty {
            arena.registerLambdaCaptureArgs(lambdaSymbol, captureArgs: captureArgs)
        }
        if !captureArgs.isEmpty,
           !needsClosureParam,
           !isSamConversion,
           let functionType
        {
            if let materialized = materializeEscapingCallableValue(
                exprID: exprID,
                lambdaSymbol: lambdaSymbol,
                lambdaReturnType: lambdaReturnType,
                functionType: functionType,
                captureArguments: captureArgs,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) {
                return materialized
            }
        }
        return lambdaValueExpr
    }

    private func materializeEscapingCallableValue(
        exprID: ExprID,
        lambdaSymbol: SymbolID,
        lambdaReturnType: TypeID,
        functionType: FunctionType,
        captureArguments: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let createCallee: InternedString
        switch functionType.params.count {
        case 0:
            createCallee = interner.intern("kk_function_create_0")
        case 1:
            createCallee = interner.intern("kk_function_create_1")
        case 2:
            createCallee = interner.intern("kk_function_create_2")
        default:
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_function_value_adapter_\(exprID.rawValue)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        let valueParams: [KIRParameter] = functionType.params.enumerated().map { index, type in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 100 + index),
                type: type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        let arrayGet = interner.intern("kk_array_get_inbounds")
        var callArguments: [KIRExprID] = []
        for (captureIndex, captureExpr) in captureArguments.enumerated() {
            let captureType = arena.exprType(captureExpr) ?? sema.types.anyType
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
            let loadedExpr = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: captureType)
            body.append(.call(
                symbol: nil,
                callee: arrayGet,
                arguments: [closureExpr, offsetExpr],
                result: loadedExpr,
                canThrow: false,
                thrownResult: nil
            ))
            callArguments.append(loadedExpr)
        }

        for param in valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            callArguments.append(paramExpr)
        }

        let callResult = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: lambdaReturnType)
        body.append(.call(
            symbol: lambdaSymbol,
            callee: syntheticLambdaName(for: exprID, interner: interner),
            arguments: callArguments,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        switch sema.types.kind(of: lambdaReturnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: adapterSymbol,
                    name: adapterName,
                    params: [closureParam] + valueParams,
                    returnType: lambdaReturnType,
                    body: body,
                    isSuspend: functionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        let slotCountExpr = arena.appendExpr(.intLiteral(Int64(2 + captureArguments.count)), type: sema.types.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(Int64(2 + captureArguments.count))))
        let classIDExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        let closureObj = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: closureObj,
            canThrow: false,
            thrownResult: nil
        ))
        for (captureIndex, captureExpr) in captureArguments.enumerated() {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
            let setResult = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [closureObj, offsetExpr, captureExpr],
                result: setResult,
                canThrow: true,
                thrownResult: nil
            ))
        }

        let adapterExpr = arena.appendExpr(.symbolRef(adapterSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: adapterExpr, value: .symbolRef(adapterSymbol)))
        let materializedExpr = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: sema.types.make(.functionType(functionType)))
        instructions.append(.call(
            symbol: nil,
            callee: createCallee,
            arguments: [adapterExpr, closureObj],
            result: materializedExpr,
            canThrow: false,
            thrownResult: nil
        ))
        return materializedExpr
    }

    private func lowerSamWrapperValue(
        _ exprID: ExprID,
        interfaceSymbol: SymbolID,
        lambdaSymbol: SymbolID,
        lambdaName: InternedString,
        lambdaReturnType: TypeID,
        captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID)],
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
        driver.ctx.appendGeneratedCallableDecl(nominalDeclID)

        let scopeSnapshot = driver.ctx.saveScope()
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()
        driver.ctx.setCurrentFunctionSymbol(methodSymbol)

        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverExpr)

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
        driver.ctx.appendGeneratedCallableDecl(methodDeclID)
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
        let isUnbound = sema.bindings.isUnboundCallableRef(exprID)
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
            // For unbound type references (Type::member), the receiver is
            // not captured — it becomes a parameter of the function type.
            if !isUnbound {
                captureArguments.append(loweredReceiver)
            }
        }

        let targetSymbol = resolveCallableRefTargetSymbol(
            exprID: exprID,
            receiverExpr: receiverExpr,
            memberName: memberName,
            sema: sema
        )

        // REFL-003: When a callable ref is used as a collection HOF argument
        // (e.g. `list.map(::double)`), we must generate a wrapper thunk with the
        // HOF ABI: (closureRaw, value, outThrown) -> result.  The target function
        // itself uses a plain ABI (value) -> result, so we cannot pass its
        // pointer directly to the runtime HOF implementation.
        let needsHOFWrapper = sema.bindings.isCollectionHOFLambdaExpr(exprID)

        let callableSymbol: SymbolID
        let callableName: InternedString
        if let targetSymbol, needsHOFWrapper {
            // Generate a HOF-ABI wrapper that delegates to the target function.
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)

            let targetName = callableTargetName(for: targetSymbol, sema: sema, interner: interner)
            let functionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(ft) = sema.types.kind(of: typeID) else { return nil }
                return ft
            }
            let valueParamTypes = functionType?.params ?? []
            let returnType = functionType?.returnType ?? sema.types.anyType

            // Build wrapper params: (closureRaw, value0, ..., valueN)
            let closureParam = KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: sema.types.intType
            )
            let valueParams: [KIRParameter] = valueParamTypes.enumerated().map { index, type in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: type
                )
            }
            let wrapperParams = [closureParam] + valueParams

            // Build wrapper body: call the target function with the value params,
            // then return its result.
            var body: [KIRInstruction] = [.beginBlock]
            var callArgExprs: [KIRExprID] = []
            // If the callable ref has a bound receiver, pass capture args first.
            for _ in captureArguments {
                let captureRef = arena.appendExpr(
                    .symbolRef(closureParam.symbol),
                    type: closureParam.type
                )
                body.append(.constValue(result: captureRef, value: .symbolRef(closureParam.symbol)))
                callArgExprs.append(captureRef)
            }
            for valueParam in valueParams {
                let paramExpr = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
                body.append(.constValue(result: paramExpr, value: .symbolRef(valueParam.symbol)))
                let normalizedParamExpr = normalizeHOFPrimitiveParameter(
                    paramExpr,
                    type: valueParam.type,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body
                )
                callArgExprs.append(normalizedParamExpr)
            }
            let callResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: returnType
            )
            body.append(.call(
                symbol: targetSymbol,
                callee: targetName,
                arguments: callArgExprs,
                result: callResult,
                canThrow: false,
                thrownResult: nil
            ))
            switch sema.types.kind(of: returnType) {
            case .unit, .nothing(.nonNull), .nothing(.nullable):
                body.append(.returnUnit)
            default:
                body.append(.returnValue(callResult))
            }
            body.append(.endBlock)

            let wrapperDecl = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: callableSymbol,
                        name: callableName,
                        params: wrapperParams,
                        returnType: returnType,
                        body: body,
                        isSuspend: functionType?.isSuspend ?? false,
                        isInline: false
                    )
                )
            )
            driver.ctx.appendGeneratedCallableDecl(wrapperDecl)
        } else if let targetSymbol {
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
            driver.ctx.appendGeneratedCallableDecl(fallbackDecl)
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

        // Collection HOF runtimes expect a raw function pointer plus closure payload.
        // Returning a tagged callable reference here would pass the reflection wrapper
        // object to runtime HOF entry points instead of the generated thunk symbol.
        if needsHOFWrapper {
            return callableExpr
        }

        // REFL-003: Emit KFunction / KProperty type identity tag.
        // The tagging call wraps the callable value with reflection
        // metadata (name, arity, KFunction vs KProperty).  We register
        // the tagged expression with the same callable-value metadata so
        // that downstream callable-value-call lowering resolves the
        // correct target symbol and capture arguments.
        if let refKind = sema.bindings.callableRefKind(for: exprID) {
            let taggedExpr = emitCallableRefTypeTag(
                callableExpr: callableExpr,
                callableType: callableType,
                refKind: refKind,
                memberName: memberName,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            driver.ctx.registerCallableValue(
                taggedExpr,
                symbol: callableSymbol,
                callee: callableName,
                captureArguments: captureArguments
            )
            return taggedExpr
        }

        return callableExpr
    }

    // MARK: - REFL-003: Callable reference type identity

    /// Emits a runtime tagging call that annotates a callable reference value
    /// with KFunction or KProperty type identity. Returns a new KIR expression
    /// representing the tagged value.  The caller must use the returned
    /// expression (and register it for callable-value resolution) so that the
    /// tagged value propagates through the program.
    func emitCallableRefTypeTag(
        callableExpr: KIRExprID,
        callableType: TypeID,
        refKind: CallableRefKind,
        memberName: InternedString,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Compute arity from the function type (number of value parameters).
        let arity: Int64
        if case let .functionType(functionType) = sema.types.kind(of: callableType) {
            arity = Int64(functionType.params.count)
        } else {
            // Property references have arity 0 (no value params, just a getter).
            arity = 0
        }

        // Emit the name string literal.
        let nameExpr = arena.appendExpr(
            .stringLiteral(memberName),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(memberName)))

        // Emit the arity literal.
        let arityExpr = arena.appendExpr(.intLiteral(arity), type: sema.types.intType)
        instructions.append(.constValue(result: arityExpr, value: .intLiteral(arity)))

        // Choose the tagging callee based on callable reference kind.
        let tagCallee: String = switch refKind {
        case .functionRef:
            "kk_callable_ref_tag_kfunction"
        case .propertyRef:
            "kk_callable_ref_tag_kproperty"
        }

        // Emit the tagging call.
        let taggedExpr = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: callableType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(tagCallee),
            arguments: [callableExpr, nameExpr, arityExpr],
            result: taggedExpr,
            canThrow: false,
            thrownResult: nil
        ))
        return taggedExpr
    }

    // MARK: - Non-Capturing Lambda Optimization

    /// Lowers a non-capturing lambda with optimized function pointer generation
    private func lowerNonCapturingLambda(
        exprID: ExprID,
        params: [InternedString],
        bodyExpr: ExprID,
        effectiveParamCount: Int,
        lambdaParameterTypes: [TypeID],
        lambdaReturnType: TypeID,
        functionType: FunctionType?,
        isSamConversion: Bool,
        boundType: TypeID?,
        effectiveFuncTypeID: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let lambdaName = syntheticLambdaName(for: exprID, interner: interner)
        let lambdaSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)

        // Create optimized lambda parameters (no capture parameters needed)
        let lambdaParameters = (0 ..< effectiveParamCount).map { index in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                type: lambdaParameterTypes[index]
            )
        }

        // Generate optimized lambda body
        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()

        var lambdaBody: [KIRInstruction] = [.beginBlock]
        
        // Set up parameters only (no captures)
        for (paramIndex, lambdaParam) in lambdaParameters.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(lambdaParam.symbol), type: lambdaParam.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(lambdaParam.symbol)))
            driver.ctx.setLocalValue(paramExpr, for: lambdaParam.symbol)
            
            // Handle receiver parameter if needed
            if paramIndex == 0, functionType?.receiver != nil {
                driver.ctx.setImplicitReceiver(symbol: lambdaParam.symbol, exprID: paramExpr)
            }
        }

        // Set up parameter name mapping for `it` parameter
        let effectiveParamNames: [InternedString] = if params.isEmpty, let functionType, !functionType.params.isEmpty {
            [interner.intern("it")]
        } else {
            params
        }
        for (i, paramName) in effectiveParamNames.enumerated() where i < lambdaParameters.count {
            driver.ctx.registerLambdaParam(symbol: lambdaParameters[i].symbol, forName: paramName)
        }

        // Lower the body
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

        // Create optimized function declaration
        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: lambdaParameters, // No capture parameters
                    returnType: lambdaReturnType,
                    body: lambdaBody,
                    isSuspend: functionType?.isSuspend ?? false,
                    isInline: true // Mark as inline for better optimization
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(lambdaDecl)

        // Handle SAM conversion if needed
        if isSamConversion,
           let boundType,
           case let .classType(interfaceType) = sema.types.kind(of: boundType),
           let samValue = lowerSamWrapperValue(
               exprID,
               interfaceSymbol: interfaceType.classSymbol,
               lambdaSymbol: lambdaSymbol,
               lambdaName: lambdaName,
               lambdaReturnType: lambdaReturnType,
               captureBindings: [], // No captures for non-capturing lambda
               samMethodParamTypes: lambdaParameterTypes,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return samValue
        }

        // Create optimized lambda value
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
        
        // Register with no capture arguments for optimization
        driver.ctx.registerCallableValue(
            lambdaValueExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: [], // Empty for non-capturing lambda
            hasClosureParam: false
        )
        
        return lambdaValueExpr
    }
}
