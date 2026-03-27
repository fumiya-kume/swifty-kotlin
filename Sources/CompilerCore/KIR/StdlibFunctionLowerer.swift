import Foundation

/// 標準ライブラリ関数のローワーリングを担当する専門クラス
/// Enum、比較、ループ、配列コンストラクタ、時間計測などの標準ライブラリ関数を処理する
final class StdlibFunctionLowerer {
    private unowned let coordinator: CallLoweringCoordinator
    
    init(coordinator: CallLoweringCoordinator) {
        self.coordinator = coordinator
    }
    
    // MARK: - 主要な標準ライブラリ関数処理
    
    /// 標準ライブラリ関数コールのローワーリングを試行
    func lowerStdlibFunction(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        
        // Enum関連関数
        if let enumResult = lowerEnumFunctions(exprID: exprID, args: args, context: &context) {
            return enumResult
        }
        
        // 比較関数
        if let comparisonResult = lowerComparisonFunctions(exprID: exprID, args: args, context: &context) {
            return comparisonResult
        }
        
        // ループ関数
        if let loopResult = lowerLoopFunctions(exprID: exprID, args: args, context: &context) {
            return loopResult
        }
        
        // 配列コンストラクタ
        if let arrayResult = lowerArrayConstructor(exprID: exprID, args: args, context: &context) {
            return arrayResult
        }
        
        // 時間計測関数
        if let timeResult = lowerTimeMeasurementFunctions(exprID: exprID, args: args, context: &context) {
            return timeResult
        }
        
        // typeOf関数
        if let typeOfResult = lowerTypeOfFunction(exprID: exprID, calleeExpr: calleeExpr, context: &context) {
            return typeOfResult
        }
        
        // generateSequence関数
        if let sequenceResult = lowerGenerateSequenceFunction(exprID: exprID, args: args, context: &context) {
            return sequenceResult
        }
        
        // スコープ関数
        if let scopeResult = lowerScopeFunctions(exprID: exprID, args: args, context: &context) {
            return scopeResult
        }
        
        return nil
    }
    
    // MARK: - Enum関数
    
    /// Enum関連の標準ライブラリ関数を処理
    private func lowerEnumFunctions(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        // enumValues<T>() 処理
        if let enumValuesResult = lowerEnumValuesCall(exprID: exprID, args: args, context: &context) {
            return enumValuesResult
        }
        
        // enumEntries<T>() 処理
        if let enumEntriesResult = lowerEnumEntriesCall(exprID: exprID, args: args, context: &context) {
            return enumEntriesResult
        }
        
        // enumValueOf<T>(String) 処理
        if let enumValueOfResult = lowerEnumValueOfCall(exprID: exprID, args: args, context: &context) {
            return enumValueOfResult
        }
        
        return nil
    }
    
    /// enumValues<T>() のローワーリング
    private func lowerEnumValuesCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard args.isEmpty,
              let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              symbol.kind == .function,
              let signature = sema.symbols.functionSignature(for: chosen),
              signature.reifiedTypeParameterIndices.count == 1 else {
            return nil
        }
        
        // Reified型パラメータからEnumシンボルを取得
        let enumTypeParam = signature.reifiedTypeParameterIndices[0]
        let concreteEnumType = enumTypeParam < callBinding.substitutedTypeArguments.count ?
            callBinding.substitutedTypeArguments[enumTypeParam] : sema.types.anyType
        
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(concreteEnumType)),
              let enumSymbol = sema.symbols.symbol(classType.classSymbol),
              enumSymbol.kind == .enum else {
            return nil
        }
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        let enumTypeID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: enumSymbol, sema: sema, interner: interner)
        let enumTypeIDExpr = arena.appendExpr(.intLiteral(enumTypeID), type: sema.types.intType)
        context.append(.constValue(result: enumTypeIDExpr, value: .intLiteral(enumTypeID)))
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_enum_values"),
            arguments: [enumTypeIDExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    /// enumEntries<T>() のローワーリング
    private func lowerEnumEntriesCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard args.isEmpty,
              let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              symbol.kind == .function,
              let signature = sema.symbols.functionSignature(for: chosen),
              signature.reifiedTypeParameterIndices.count == 1 else {
            return nil
        }
        
        // Reified型パラメータからEnumシンボルを取得
        let enumTypeParam = signature.reifiedTypeParameterIndices[0]
        let concreteEnumType = enumTypeParam < callBinding.substitutedTypeArguments.count ?
            callBinding.substitutedTypeArguments[enumTypeParam] : sema.types.anyType
        
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(concreteEnumType)),
              let enumSymbol = sema.symbols.symbol(classType.classSymbol),
              enumSymbol.kind == .enum else {
            return nil
        }
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        let enumTypeID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: enumSymbol, sema: sema, interner: interner)
        let enumTypeIDExpr = arena.appendExpr(.intLiteral(enumTypeID), type: sema.types.intType)
        context.append(.constValue(result: enumTypeIDExpr, value: .intLiteral(enumTypeID)))
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_enum_entries"),
            arguments: [enumTypeIDExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    /// enumValueOf<T>(String) のローワーリング
    private func lowerEnumValueOfCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard args.count == 1,
              let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              symbol.kind == .function,
              let signature = sema.symbols.functionSignature(for: chosen),
              signature.reifiedTypeParameterIndices.count == 1 else {
            return nil
        }
        
        // Reified型パラメータからEnumシンボルを取得
        let enumTypeParam = signature.reifiedTypeParameterIndices[0]
        let concreteEnumType = enumTypeParam < callBinding.substitutedTypeArguments.count ?
            callBinding.substitutedTypeArguments[enumTypeParam] : sema.types.anyType
        
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(concreteEnumType)),
              let enumSymbol = sema.symbols.symbol(classType.classSymbol),
              enumSymbol.kind == .enum else {
            return nil
        }
        
        // 文字列引数のローワーリング
        let stringArgID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        let enumTypeID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: enumSymbol, sema: sema, interner: interner)
        let enumTypeIDExpr = arena.appendExpr(.intLiteral(enumTypeID), type: sema.types.intType)
        context.append(.constValue(result: enumTypeIDExpr, value: .intLiteral(enumTypeID)))
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_enum_value_of"),
            arguments: [enumTypeIDExpr, stringArgID],
            result: result,
            canThrow: true,
            thrownResult: nil
        ))
        
        return result
    }
    
    // MARK: - 比較関数
    
    /// 比較関連の標準ライブラリ関数を処理
    private func lowerComparisonFunctions(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        
        // 比較関数の特殊処理
        if let comparisonResult = lowerComparisonSpecialCall(exprID: exprID, args: args, context: &context) {
            return comparisonResult
        }
        
        return nil
    }
    
    /// 特殊な比較関数を処理
    private func lowerComparisonSpecialCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen) else {
            return nil
        }
        
        let calleeName = interner.resolve(symbol.name)
        
        // maxOf/minOf 関数の処理
        if (calleeName == "maxOf" || calleeName == "minOf") && args.count >= 2 {
            return handleMaxMinFunctions(
                calleeName: calleeName,
                args: args,
                result: result,
                context: &context
            )
        }
        
        return nil
    }
    
    /// maxOf/minOf 関数を処理
    private func handleMaxMinFunctions(
        calleeName: String,
        args: [CallArgument],
        result: KIRExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        let runtimeName = calleeName == "maxOf" ? "kk_max_of" : "kk_min_of"
        let loweredArgs = args.map { arg in
            coordinator.driver.lowerExpr(
                arg.expr,
                shared: context.sharedContext,
                emit: context.emitContext()
            )
        }
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeName),
            arguments: loweredArgs,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    // MARK: - ループ関数
    
    /// ループ関連の標準ライブラリ関数を処理
    private func lowerLoopFunctions(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        
        // repeat関数
        if let repeatResult = lowerRepeatCall(exprID: exprID, args: args, context: &context) {
            return repeatResult
        }
        
        return nil
    }
    
    /// repeat関数のローワーリング
    private func lowerRepeatCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        guard args.count == 2,
              let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              interner.resolve(symbol.name) == "repeat" else {
            return nil
        }
        
        let timesArgID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let actionArgID = coordinator.driver.lowerExpr(
            args[1].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let result = arena.appendExpr(.unit, type: sema.types.unitType)
        context.append(.constValue(result: result, value: .unit))
        
        // repeat関数の実装
        // TODO: 実際のrepeat実装ロジックを追加
        
        return result
    }
    
    // MARK: - 配列コンストラクタ
    
    /// 配列コンストラクタを処理
    private func lowerArrayConstructor(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        
        if let arrayResult = lowerArrayConstructorCall(exprID: exprID, args: args, context: &context) {
            return arrayResult
        }
        
        return nil
    }
    
    /// 配列コンストラクタコールのローワーリング
    private func lowerArrayConstructorCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              interner.resolve(symbol.name) == "arrayOf" else {
            return nil
        }
        
        let loweredArgs = args.map { arg in
            coordinator.driver.lowerExpr(
                arg.expr,
                shared: context.sharedContext,
                emit: context.emitContext()
            )
        }
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        // 配列サイズ
        let sizeExpr = arena.appendExpr(.intLiteral(Int64(args.count)), type: sema.types.intType)
        context.append(.constValue(result: sizeExpr, value: .intLiteral(Int64(args.count))))
        
        // 配列のアロケーションと初期化
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_of"),
            arguments: [sizeExpr] + loweredArgs,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    // MARK: - 時間計測関数
    
    /// 時間計測関連の標準ライブラリ関数を処理
    private func lowerTimeMeasurementFunctions(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        
        // measureTimeMillis
        if let timeResult = lowerMeasureTimeMillisCall(exprID: exprID, args: args, context: &context) {
            return timeResult
        }
        
        // measureNanoTime
        if let nanoResult = lowerMeasureNanoTimeCall(exprID: exprID, args: args, context: &context) {
            return nanoResult
        }
        
        // measureTime
        if let timeResult = lowerMeasureTimeCall(exprID: exprID, args: args, context: &context) {
            return timeResult
        }
        
        // measureTimedValue
        if let timedValueResult = lowerMeasureTimedValueCall(exprID: exprID, args: args, context: &context) {
            return timedValueResult
        }
        
        return nil
    }
    
    /// measureTimeMillisのローワーリング
    private func lowerMeasureTimeMillisCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard args.count == 1,
              let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              interner.resolve(symbol.name) == "measureTimeMillis" else {
            return nil
        }
        
        let actionArgID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_measure_time_millis"),
            arguments: [actionArgID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    /// measureNanoTimeのローワーリング
    private func lowerMeasureNanoTimeCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard args.count == 1,
              let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              interner.resolve(symbol.name) == "measureNanoTime" else {
            return nil
        }
        
        let actionArgID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_measure_nano_time"),
            arguments: [actionArgID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    /// measureTimeのローワーリング
    private func lowerMeasureTimeCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard args.count == 1,
              let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              interner.resolve(symbol.name) == "measureTime" else {
            return nil
        }
        
        let actionArgID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_measure_time"),
            arguments: [actionArgID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    /// measureTimedValueのローワーリング
    private func lowerMeasureTimedValueCall(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard args.count == 1,
              let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              interner.resolve(symbol.name) == "measureTimedValue" else {
            return nil
        }
        
        let actionArgID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_measure_timed_value"),
            arguments: [actionArgID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    // MARK: - typeOf関数
    
    /// typeOf<T>() 関数を処理
    private func lowerTypeOfFunction(
        exprID: ExprID,
        calleeExpr: ExprID,
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              interner.resolve(symbol.name) == "typeOf",
              let signature = sema.symbols.functionSignature(for: chosen),
              signature.reifiedTypeParameterIndices.count == 1 else {
            return nil
        }
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        
        // Reified型パラメータから型情報を取得
        let typeParamIndex = signature.reifiedTypeParameterIndices[0]
        let concreteType = typeParamIndex < callBinding.substitutedTypeArguments.count ?
            callBinding.substitutedTypeArguments[typeParamIndex] : sema.types.anyType
        
        // KTypeオブジェクトの生成
        let kTypeExpr = lowerKTypeExpr(for: concreteType, context: &context)
        
        context.append(.copy(from: kTypeExpr, to: result))
        return result
    }
    
    /// KType式をローワーリング
    private func lowerKTypeExpr(
        for type: TypeID,
        context: inout CallLoweringContext
    ) -> KIRExprID {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        
        // 型トークンのエンコード
        let typeToken = RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: interner)
        let typeTokenExpr = arena.appendExpr(.intLiteral(typeToken), type: sema.types.intType)
        context.append(.constValue(result: typeTokenExpr, value: .intLiteral(typeToken)))
        
        // KTypeオブジェクトの生成
        let kTypeResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.kTypeType)
        context.append(.call(
            symbol: nil,
            callee: interner.intern("kk_typeof"),
            arguments: [typeTokenExpr],
            result: kTypeResult,
            canThrow: false,
            thrownResult: nil
        ))
        
        return kTypeResult
    }
    
    // MARK: - generateSequence関数
    
    /// generateSequence関数を処理
    private func lowerGenerateSequenceFunction(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard args.count == 2,
              let callBinding = sema.bindings.callBindings[exprID],
              let chosen = callBinding.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              interner.resolve(symbol.name) == "generateSequence" else {
            return nil
        }
        
        let seedFunctionType = sema.bindings.exprTypes[args[0].expr]
        guard case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(seedFunctionType)),
              functionType.params.isEmpty else {
            return nil
        }
        
        let seedArgID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let nextArgID = coordinator.driver.lowerExpr(
            args[1].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        guard let seedCallableInfo = coordinator.driver.ctx.callableValueInfo(for: seedArgID) else {
            return nil
        }
        
        let seedResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: sema.types.makeNonNullable(functionType.returnType)
        )
        
        context.append(.call(
            symbol: seedCallableInfo.symbol,
            callee: seedCallableInfo.callee,
            arguments: seedCallableInfo.captureArguments,
            result: seedResult,
            canThrow: false,
            thrownResult: nil
        ))
        
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        context.append(.call(
            symbol: chosen,
            callee: interner.intern("kk_sequence_generate"),
            arguments: [seedResult, nextArgID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        
        return result
    }
    
    // MARK: - スコープ関数
    
    /// スコープ関数を処理
    private func lowerScopeFunctions(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let interner = context.interner
        
        // with関数
        if let withResult = lowerWithFunction(exprID: exprID, args: args, context: &context) {
            return withResult
        }
        
        // run関数
        if let runResult = lowerRunFunction(exprID: exprID, args: args, context: &context) {
            return runResult
        }
        
        return nil
    }
    
    /// with関数のローワーリング
    private func lowerWithFunction(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
              scopeKind == .scopeWith,
              args.count == 2 else {
            return nil
        }
        
        let loweredReceiverID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        // 暗黙的レシーバーの設定
        let receiverSymbol = coordinator.driver.ctx.allocateSyntheticGeneratedSymbol()
        let receiverType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
        let receiverSymExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
        context.append(.copy(from: loweredReceiverID, to: receiverSymExpr))
        
        let savedReceiverExprID = coordinator.driver.ctx.activeImplicitReceiverExprID()
        let savedReceiverSymbol = coordinator.driver.ctx.activeImplicitReceiverSymbol()
        coordinator.driver.ctx.setLocalValue(receiverSymExpr, for: receiverSymbol)
        coordinator.driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverSymExpr)
        
        let loweredLambdaID = coordinator.driver.lowerExpr(
            args[1].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        coordinator.driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)
        
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: boundType
        )
        
        if let info = coordinator.driver.ctx.callableValueInfo(for: loweredLambdaID) {
            context.append(.call(
                symbol: info.symbol,
                callee: info.callee,
                arguments: info.captureArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
        
        return result
    }
    
    /// run関数のローワーリング
    private func lowerRunFunction(
        exprID: ExprID,
        args: [CallArgument],
        context: inout CallLoweringContext
    ) -> KIRExprID? {
        let sema = context.sema
        let arena = context.arena
        let interner = context.interner
        let boundType = sema.bindings.exprTypes[exprID]
        
        guard let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
              scopeKind == .scopeTopLevelRun,
              args.count == 1 else {
            return nil
        }
        
        let loweredLambdaID = coordinator.driver.lowerExpr(
            args[0].expr,
            shared: context.sharedContext,
            emit: context.emitContext()
        )
        
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: boundType
        )
        
        if let info = coordinator.driver.ctx.callableValueInfo(for: loweredLambdaID) {
            context.append(.call(
                symbol: info.symbol,
                callee: info.callee,
                arguments: info.captureArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            // 呼び出し可能参照の場合
            let invokeName = interner.intern("invoke")
            context.append(.call(
                symbol: nil,
                callee: invokeName,
                arguments: [loweredLambdaID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
        
        return result
    }
}
