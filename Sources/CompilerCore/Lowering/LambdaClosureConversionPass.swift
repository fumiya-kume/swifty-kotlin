import Foundation

/// CLSR-001: Closure object synthesis pass.
///
/// Lambda functions produced by `LambdaLowerer` use flat closure conversion:
/// capture values are prepended as extra function parameters, and call sites
/// pass them directly.  This works for direct calls but prevents lambdas from
/// being stored, passed, or invoked polymorphically.
///
/// This pass rewrites the KIR so that each lambda with captures gets a stable
/// closure object:
///
///  1. A synthetic `kk_closure_obj_<N>` nominal marker type is created so the
///     runtime can identify closure boxes by class ID.
///  2. A synthetic `kk_closure_invoke_<N>` wrapper function is created that
///     loads captures from the object and forwards to the original lambda.
///  3. Call sites that previously prepended capture arguments are rewritten to
///     allocate a closure object, store captures into it, and call the invoke
///     wrapper instead.
///
/// The `<lambda>` marker calls (used by the test fixture) are still rewritten
/// to `kk_lambda_invoke` for backward compatibility.
final class LambdaClosureConversionPass: LoweringPass {
    static let name = "LambdaClosureConversion"

    // MARK: - Analysis types

    /// Information about a lambda function with captures.
    private struct LambdaCaptureInfo {
        let function: KIRFunction
        let captureParamCount: Int
        let valueParamCount: Int

        var captureParams: [KIRParameter] {
            Array(function.params.prefix(captureParamCount))
        }

        var valueParams: [KIRParameter] {
            Array(function.params.suffix(valueParamCount))
        }
    }

    private struct InvokeWrapperInfo: Hashable {
        let name: InternedString
        let symbol: SymbolID
    }

    /// Pre-computed call-site index to avoid repeated O(#functions * #instructions)
    /// scans during capture-count validation and throwing detection.
    private struct CallSiteIndex {
        /// For each callee (by symbol or name), the observed argument counts.
        var arityBySymbol: [SymbolID: Set<Int>] = [:]
        var arityByName: [InternedString: Set<Int>] = [:]
        /// For each callee (by symbol or name), whether any call site has canThrow == true.
        var throwingBySymbol: Set<SymbolID> = []
        var throwingByName: Set<InternedString> = []

        static func build(from module: KIRModule) -> CallSiteIndex {
            var index = CallSiteIndex()
            for decl in module.arena.declarations {
                guard case let .function(fn) = decl else { continue }
                for instruction in fn.body {
                    if case let .call(symbol, callee, arguments, _, canThrow, _, _, _) = instruction {
                        let arity = arguments.count
                        if let symbol {
                            index.arityBySymbol[symbol, default: []].insert(arity)
                            if canThrow {
                                index.throwingBySymbol.insert(symbol)
                            }
                        }
                        index.arityByName[callee, default: []].insert(arity)
                        if canThrow {
                            index.throwingByName.insert(callee)
                        }
                    }
                }
            }
            return index
        }

        func hasCallSiteWithArity(symbol: SymbolID, name: InternedString, arity: Int) -> Bool {
            if let arities = arityBySymbol[symbol], arities.contains(arity) {
                return true
            }
            if let arities = arityByName[name], arities.contains(arity) {
                return true
            }
            return false
        }

        func isCalledWithCanThrow(symbol: SymbolID, name: InternedString) -> Bool {
            return throwingBySymbol.contains(symbol) || throwingByName.contains(name)
        }
    }

    // MARK: - shouldRun

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        let markerCallee = ctx.interner.intern("<lambda>")
        let lambdaPrefix = "kk_lambda_"

        // Build call-site index once for shouldRun checks.
        let callSiteIndex = CallSiteIndex.build(from: module)

        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                if case let .call(_, callee, _, _, _, _, _, _) = instruction,
                   callee == markerCallee
                {
                    return true
                }
            }
            let name = ctx.interner.resolve(function.name)
            if name.hasPrefix(lambdaPrefix),
               detectCaptureParamCount(
                   function: function,
                   lambdaExprID: lambdaExprID(from: function.name, interner: ctx.interner),
                   callSiteIndex: callSiteIndex
               ) > 0,
               !callSiteIndex.isCalledWithCanThrow(
                   symbol: function.symbol,
                   name: function.name
               )
            {
                return true
            }
        }
        return false
    }

    // MARK: - run

    func run(module: KIRModule, ctx: KIRContext) throws {
        let interner = ctx.interner
        let markerCallee = interner.intern("<lambda>")
        let loweredCallee = interner.intern("kk_lambda_invoke")

        // Closure object synthesis (Phases 1+2) requires valid sema to derive
        // TypeIDs for synthesized instructions.  Without sema we still rewrite
        // <lambda> markers (Phase 3) but skip closure object creation to avoid
        // emitting malformed KIR with TypeID.invalid.
        let sema = ctx.sema

        var captureInfoBySymbol: [SymbolID: LambdaCaptureInfo] = [:]
        var captureInfoByName: [InternedString: LambdaCaptureInfo] = [:]
        var invokeWrapperByLambdaSymbol: [SymbolID: InvokeWrapperInfo] = [:]
        var invokeWrapperNames: Set<InternedString> = []
        var intType: TypeID = TypeID.invalid
        var anyType: TypeID = TypeID.invalid

        if let sema {
            // Build call-site index once for all analysis (capture-count
            // validation and canThrow detection).
            let callSiteIndex = CallSiteIndex.build(from: module)

            // Phase 1: Identify lambda functions with captures.
            let lambdaInfos = identifyLambdasWithCaptures(
                module: module,
                ctx: ctx,
                callSiteIndex: callSiteIndex
            )

            for info in lambdaInfos {
                captureInfoBySymbol[info.function.symbol] = info
                captureInfoByName[info.function.name] = info
            }

            // Phase 2: For each lambda with captures, synthesize a closure object
            // and invoke wrapper.
            for info in lambdaInfos {
                let (invokeWrapperName, invokeWrapperSymbol, newDecls) = synthesizeClosureObject(
                    lambdaInfo: info,
                    module: module,
                    ctx: ctx,
                    sema: sema
                )
                invokeWrapperByLambdaSymbol[info.function.symbol] = InvokeWrapperInfo(
                    name: invokeWrapperName,
                    symbol: invokeWrapperSymbol
                )
                for decl in newDecls {
                    _ = module.arena.appendDecl(decl)
                }

                // Register both the invoke wrapper and its internal lambda target
                // as non-throwing callees so ABILoweringPass can consult
                // module.nonThrowingClosureCallees instead of relying on
                // string-prefix conventions.
                module.registerNonThrowingClosureCallee(invokeWrapperName)
                module.registerNonThrowingClosureCallee(info.function.name)
            }

            invokeWrapperNames = Set(invokeWrapperByLambdaSymbol.values.map(\.name))
            intType = sema.types.make(.primitive(.int, .nonNull))
            anyType = sema.types.anyType
        }

        // Phase 3: Rewrite call sites (marker rewriting works without sema;
        // closure-object rewriting only triggers when captureInfoBySymbol is
        // populated, which requires sema above).
        module.arena.transformFunctions { function in
            // Skip invoke wrappers: they already load captures from
            // the closure object and forward to the original lambda.
            if invokeWrapperNames.contains(function.name) {
                return function
            }
            return self.rewriteCallSites(
                function: function,
                markerCallee: markerCallee,
                loweredCallee: loweredCallee,
                captureInfoBySymbol: captureInfoBySymbol,
                captureInfoByName: captureInfoByName,
                invokeWrapperByLambdaSymbol: invokeWrapperByLambdaSymbol,
                module: module,
                ctx: ctx,
                intType: intType,
                anyType: anyType
            )
        }

        module.recordLowering(Self.name)
    }

    // MARK: - Phase 1: Identify lambdas with captures

    private func identifyLambdasWithCaptures(
        module: KIRModule,
        ctx: KIRContext,
        callSiteIndex: CallSiteIndex
    ) -> [LambdaCaptureInfo] {
        let lambdaPrefix = "kk_lambda_"
        var results: [LambdaCaptureInfo] = []

        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            let name = ctx.interner.resolve(function.name)
            guard name.hasPrefix(lambdaPrefix), function.params.count > 0 else {
                continue
            }

            let lambdaExprID = lambdaExprID(from: function.name, interner: ctx.interner)
            let captureCount = detectCaptureParamCount(
                function: function,
                lambdaExprID: lambdaExprID,
                callSiteIndex: callSiteIndex
            )
            if captureCount > 0 {
                if callSiteIndex.isCalledWithCanThrow(
                    symbol: function.symbol,
                    name: function.name
                ) {
                    continue
                }

                results.append(LambdaCaptureInfo(
                    function: function,
                    captureParamCount: captureCount,
                    valueParamCount: function.params.count - captureCount
                ))
            }
        }

        return results
    }

    /// Capture params use synthetic negative SymbolIDs in the range
    /// -2_000_000... (from `syntheticLambdaCaptureParamSymbol`).
    private func detectCaptureParamCount(
        function: KIRFunction,
        lambdaExprID: Int64?,
        callSiteIndex: CallSiteIndex
    ) -> Int {
        var captureCount = 0
        for param in function.params {
            if isCaptureParamSymbol(param.symbol, lambdaExprID: lambdaExprID) {
                captureCount += 1
            } else {
                break
            }
        }

        guard captureCount > 0 else {
            return 0
        }

        // Skip lambdas that consist of ONLY capture parameters with zero value
        // parameters.  These are scope-function lambdas (apply, run) where the
        // receiver `this` is the sole capture and the block takes no explicit
        // arguments.  Wrapping these in a closure object breaks receiver-based
        // member resolution because the loaded capture loses its concrete type.
        let valueParamCount = function.params.count - captureCount
        if valueParamCount == 0 {
            return 0
        }

        // Validate: at least one call site passes the full lambda arity.
        // Uses the pre-computed call-site index instead of scanning all
        // functions/instructions, reducing complexity from O(#lambdas * #instructions)
        // to O(1) per lambda.
        if callSiteIndex.hasCallSiteWithArity(
            symbol: function.symbol,
            name: function.name,
            arity: function.params.count
        ) {
            return captureCount
        }

        return 0
    }

    /// Returns true if the symbol is in the synthetic capture-param range.
    /// LambdaLowerer uses:
    ///   - Value params:   rawValue around -1_000_000 (syntheticLambdaParamSymbol)
    ///   - Capture params: rawValue around -2_000_000 (syntheticLambdaCaptureParamSymbol)
    /// We compute the midpoint between their ranges for the lambda exprID.
    private func isCaptureParamSymbol(_ symbol: SymbolID, lambdaExprID: Int64?) -> Bool {
        let exprID = lambdaExprID ?? 0
        let boundary = Int64(-1_500_000) - (exprID * 256)
        return Int64(symbol.rawValue) < boundary
    }

    /// Parses lambda ExprID from names like `kk_lambda_42`.
    private func lambdaExprID(from lambdaName: InternedString, interner: StringInterner) -> Int64? {
        let rawName = interner.resolve(lambdaName)
        let prefix = "kk_lambda_"
        guard rawName.hasPrefix(prefix) else {
            return nil
        }

        return Int64(rawName.dropFirst(prefix.count))
    }

    // MARK: - Phase 2: Synthesize closure object

    private func synthesizeClosureObject(
        lambdaInfo: LambdaCaptureInfo,
        module: KIRModule,
        ctx: KIRContext,
        sema: SemaModule
    ) -> (invokeWrapperName: InternedString, invokeWrapperSymbol: SymbolID, declarations: [KIRDecl]) {
        let interner = ctx.interner
        let arena = module.arena
        let lambdaSymbolRaw = lambdaInfo.function.symbol.rawValue
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let anyType = sema.types.anyType

        // Nominal marker type for the closure object. The runtime payload is
        // stored in the array box allocated by `kk_object_new`.
        _ = interner.intern("kk_closure_obj_\(lambdaSymbolRaw)")
        let nominalSymbol = SymbolID(rawValue: Int32(clamping: -(41_000_000 + Int64(lambdaSymbolRaw))))
        let nominalDecl = KIRDecl.nominalType(KIRNominalType(symbol: nominalSymbol))

        // Invoke wrapper function.
        let invokeWrapperName = interner.intern("kk_closure_invoke_\(lambdaSymbolRaw)")
        let invokeSymbol = SymbolID(rawValue: Int32(clamping: -(42_000_000 + Int64(lambdaSymbolRaw))))

        let closureObjParamSymbol = SymbolID(rawValue: -(30_000_000 + lambdaSymbolRaw))
        let closureObjParam = KIRParameter(symbol: closureObjParamSymbol, type: anyType)
        let invokeParams = [closureObjParam] + lambdaInfo.valueParams
        let returnType = lambdaInfo.function.returnType

        var invokeBody: [KIRInstruction] = [.beginBlock]
        let kk_array_get = interner.intern("kk_array_get_inbounds")
        // Compute next temp ID from the arena's current expression count.
        // This is safe here because synthesizeClosureObject is called
        // sequentially and the arena grows monotonically.
        var nextTempID = Int32(clamping: arena.expressions.count)

        let closureObjExpr = arena.appendExpr(.symbolRef(closureObjParamSymbol), type: anyType)
        invokeBody.append(.constValue(result: closureObjExpr, value: .symbolRef(closureObjParamSymbol)))

        var loadedCaptureExprs: [KIRExprID] = []
        for captureIndex in 0 ..< lambdaInfo.captureParamCount {
            let fieldOffset = Int64(captureIndex + 2)
            let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: intType)
            invokeBody.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))

            let captureType = lambdaInfo.captureParams[captureIndex].type
            let loadedExpr = makeTemporaryExpr(arena: arena, nextTempID: &nextTempID, type: captureType)
            invokeBody.append(.call(
                symbol: nil,
                callee: kk_array_get,
                arguments: [closureObjExpr, offsetExpr],
                result: loadedExpr,
                canThrow: false,
                thrownResult: nil
            ))
            loadedCaptureExprs.append(loadedExpr)
        }

        var valueParamExprs: [KIRExprID] = []
        for valueParam in lambdaInfo.valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
            invokeBody.append(.constValue(result: paramExpr, value: .symbolRef(valueParam.symbol)))
            valueParamExprs.append(paramExpr)
        }

        let callResultExpr = makeTemporaryExpr(arena: arena, nextTempID: &nextTempID, type: returnType)
        invokeBody.append(.call(
            symbol: lambdaInfo.function.symbol,
            callee: lambdaInfo.function.name,
            arguments: loadedCaptureExprs + valueParamExprs,
            result: callResultExpr,
            canThrow: false,
            thrownResult: nil
        ))
        invokeBody.append(.returnValue(callResultExpr))
        invokeBody.append(.endBlock)

        let invokeFunction = KIRFunction(
            symbol: invokeSymbol,
            name: invokeWrapperName,
            params: invokeParams,
            returnType: returnType,
            body: invokeBody,
            isSuspend: lambdaInfo.function.isSuspend,
            isInline: false
        )
        let invokeFuncDecl = KIRDecl.function(invokeFunction)

        return (invokeWrapperName, invokeSymbol, [nominalDecl, invokeFuncDecl])
    }

    // MARK: - Phase 3: Rewrite call sites

    private func rewriteCallSites(
        function: KIRFunction,
        markerCallee: InternedString,
        loweredCallee: InternedString,
        captureInfoBySymbol: [SymbolID: LambdaCaptureInfo],
        captureInfoByName: [InternedString: LambdaCaptureInfo],
        invokeWrapperByLambdaSymbol: [SymbolID: InvokeWrapperInfo],
        module: KIRModule,
        ctx: KIRContext,
        intType: TypeID,
        anyType: TypeID
    ) -> KIRFunction {
        let interner = ctx.interner
        let arena = module.arena
        let kk_object_new = interner.intern("kk_object_new")
        let kk_array_set = interner.intern("kk_array_set")
        // Derive next temp ID from the function's maximum existing temporary ID
        // to keep numbering function-local and stable, avoiding sensitivity to
        // unrelated global expression allocations.
        var nextTempID = Self.maxTempID(in: function) + 1

        var updated = function
        var loweredBody: [KIRInstruction] = []
        loweredBody.reserveCapacity(function.body.count * 2)

        for instruction in function.body {
            switch instruction {
            case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
                if callee == markerCallee {
                    loweredBody.append(.call(
                        symbol: symbol,
                        callee: loweredCallee,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall,
                        qualifiedSuperType: qualifiedSuperType
                    ))
                    continue
                }

                let captureInfo: LambdaCaptureInfo?
                let invokeWrapper: InvokeWrapperInfo?
                if let sym = symbol, let info = captureInfoBySymbol[sym] {
                    captureInfo = info
                    invokeWrapper = invokeWrapperByLambdaSymbol[sym]
                } else if let info = captureInfoByName[callee] {
                    captureInfo = info
                    invokeWrapper = invokeWrapperByLambdaSymbol[info.function.symbol]
                } else {
                    captureInfo = nil
                    invokeWrapper = nil
                }

                if let captureInfo, let invokeWrapper,
                   arguments.count == captureInfo.function.params.count
                {
                    let captureArgs = Array(arguments.prefix(captureInfo.captureParamCount))
                    let valueArgs = Array(arguments.suffix(captureInfo.valueParamCount))

                    let slotCount = Int64(2 + captureInfo.captureParamCount)
                    let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
                    loweredBody.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))

                    let classID = closureObjectClassID(lambdaSymbol: captureInfo.function.symbol)
                    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
                    loweredBody.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))

                    let closureObjExpr = makeTemporaryExpr(arena: arena, nextTempID: &nextTempID, type: anyType)
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: kk_object_new,
                        arguments: [slotCountExpr, classIDExpr],
                        result: closureObjExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    for (captureIndex, captureArg) in captureArgs.enumerated() {
                        let fieldOffset = Int64(captureIndex + 2)
                        let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: intType)
                        loweredBody.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))

                        let unusedResult = makeTemporaryExpr(arena: arena, nextTempID: &nextTempID, type: anyType)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kk_array_set,
                            arguments: [closureObjExpr, offsetExpr, captureArg],
                            result: unusedResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }

                    loweredBody.append(.call(
                        symbol: invokeWrapper.symbol,
                        callee: invokeWrapper.name,
                        arguments: [closureObjExpr] + valueArgs,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                    continue
                }

                loweredBody.append(instruction)

            default:
                loweredBody.append(instruction)
            }
        }

        updated.replaceBody(loweredBody)
        return updated
    }

    // MARK: - Helpers

    private func makeTemporaryExpr(
        arena: KIRArena,
        nextTempID: inout Int32,
        type: TypeID
    ) -> KIRExprID {
        // Keep temp IDs stable even if we insert extra helper expressions.
        let expr = arena.appendExpr(.temporary(nextTempID), type: type)
        nextTempID += 1
        return expr
    }

    /// Compute the maximum temporary expression ID used within a function's body,
    /// scanning result expressions of all instructions.  Returns 0 if no
    /// temporaries exist, so the first synthesized temp will be 1.
    private static func maxTempID(in function: KIRFunction) -> Int32 {
        var maxID: Int32 = 0
        for instruction in function.body {
            let exprIDs: [KIRExprID?]
            switch instruction {
            case let .call(_, _, _, result, _, _, _, _):
                exprIDs = [result]
            case let .virtualCall(_, _, _, _, result, _, _, _):
                exprIDs = [result]
            case let .binary(_, _, _, result):
                exprIDs = [result]
            case let .unary(_, _, result):
                exprIDs = [result]
            case let .constValue(result, _):
                exprIDs = [result]
            case let .copy(_, to):
                exprIDs = [to]
            case let .nullAssert(_, result):
                exprIDs = [result]
            case let .loadGlobal(result, _):
                exprIDs = [result]
            default:
                exprIDs = []
            }
            for case let id? in exprIDs {
                if id.rawValue > maxID {
                    maxID = id.rawValue
                }
            }
        }
        return maxID
    }

    private func closureObjectClassID(lambdaSymbol: SymbolID) -> Int64 {
        // FNV-1a hash for stable ID.
        let name = "kk_closure_obj_\(lambdaSymbol.rawValue)"
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        let payloadMask: Int64 = (1 << 55) - 1
        let payload = Int64(bitPattern: hash) & payloadMask
        return payload == 0 ? 1 : payload
    }
}
