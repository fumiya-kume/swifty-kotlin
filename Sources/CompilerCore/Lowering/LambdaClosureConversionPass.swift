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
///  1. A synthetic `kk_closure_obj_<N>` nominal type is created.  Captures are
///     stored by convention in object/array slots starting at offset 2.
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
        /// Whether any call site invokes this lambda with `canThrow == true`.
        let canThrow: Bool

        var captureParams: [KIRParameter] {
            Array(function.params.prefix(captureParamCount))
        }

        var valueParams: [KIRParameter] {
            Array(function.params.suffix(valueParamCount))
        }
    }

    // MARK: - shouldRun

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        let markerCallee = ctx.interner.intern("<lambda>")
        let lambdaPrefix = "kk_lambda_"

        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                if case let .call(_, callee, _, _, _, _, _) = instruction,
                   callee == markerCallee
                {
                    return true
                }
            }
            let name = ctx.interner.resolve(function.name)
            if name.hasPrefix(lambdaPrefix), function.params.count > 0,
               detectCaptureParamCount(function: function, module: module) > 0 {
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

        // Phase 1: Identify lambda functions with captures.
        let lambdaInfos = identifyLambdasWithCaptures(module: module, ctx: ctx)

        var captureInfoBySymbol: [SymbolID: LambdaCaptureInfo] = [:]
        var captureInfoByName: [InternedString: LambdaCaptureInfo] = [:]
        for info in lambdaInfos {
            captureInfoBySymbol[info.function.symbol] = info
            captureInfoByName[info.function.name] = info
        }

        // Phase 2: For each lambda with captures, synthesize a closure object
        // and invoke wrapper.
        var invokeWrapperByLambdaSymbol: [SymbolID: InternedString] = [:]

        for info in lambdaInfos {
            let (invokeWrapperName, newDecls) = synthesizeClosureObject(
                lambdaInfo: info,
                module: module,
                ctx: ctx
            )
            invokeWrapperByLambdaSymbol[info.function.symbol] = invokeWrapperName
            for decl in newDecls {
                _ = module.arena.appendDecl(decl)
            }
        }

        // Collect invoke wrapper names so we skip rewriting their internal calls.
        let invokeWrapperNames = Set(invokeWrapperByLambdaSymbol.values)

        // Phase 3: Rewrite call sites.
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
                ctx: ctx
            )
        }

        module.recordLowering(Self.name)
    }

    // MARK: - Phase 1: Identify lambdas with captures

    private func identifyLambdasWithCaptures(
        module: KIRModule,
        ctx: KIRContext
    ) -> [LambdaCaptureInfo] {
        let lambdaPrefix = "kk_lambda_"
        var results: [LambdaCaptureInfo] = []

        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            let name = ctx.interner.resolve(function.name)
            guard name.hasPrefix(lambdaPrefix), function.params.count > 0 else {
                continue
            }

            let captureCount = detectCaptureParamCount(
                function: function,
                module: module
            )
            if captureCount > 0 {
                let throws_ = detectCanThrow(
                    lambdaName: function.name,
                    lambdaSymbol: function.symbol,
                    module: module
                )
                results.append(LambdaCaptureInfo(
                    function: function,
                    captureParamCount: captureCount,
                    valueParamCount: function.params.count - captureCount,
                    canThrow: throws_
                ))
            }
        }

        return results
    }

    /// Capture params use synthetic negative SymbolIDs in the range
    /// -2_000_000... (from `syntheticLambdaCaptureParamSymbol`).
    private func detectCaptureParamCount(
        function: KIRFunction,
        module: KIRModule
    ) -> Int {
        var captureCount = 0
        for param in function.params {
            if param.symbol.rawValue <= -2, isCaptureParamSymbol(param.symbol) {
                captureCount += 1
            } else {
                break
            }
        }

        // Validate: at least one call site passes exactly the expected arg count.
        // If no matching call site exists (dead code, partially optimized lambda),
        // return 0 so we do not synthesize an unnecessary closure object.
        if captureCount > 0 {
            let lambdaName = function.name
            let totalExpected = function.params.count
            for decl in module.arena.declarations {
                guard case let .function(callerFn) = decl,
                      callerFn.symbol != function.symbol
                else { continue }
                for instruction in callerFn.body {
                    if case let .call(_, callee, arguments, _, _, _, _) = instruction,
                       callee == lambdaName,
                       arguments.count == totalExpected
                    {
                        return captureCount
                    }
                }
            }
        }

        return 0
    }

    /// Returns true if the symbol is in the synthetic capture-param range.
    /// LambdaLowerer uses:
    ///   - Value params:   rawValue around -1_000_000 (syntheticLambdaParamSymbol)
    ///   - Capture params: rawValue around -2_000_000 (syntheticLambdaCaptureParamSymbol)
    /// We use -1_500_000 as the boundary.
    private func isCaptureParamSymbol(_ symbol: SymbolID) -> Bool {
        symbol.rawValue < -1_500_000
    }

    /// Returns true if any call site invokes this lambda with `canThrow == true`.
    private func detectCanThrow(
        lambdaName: InternedString,
        lambdaSymbol: SymbolID,
        module: KIRModule
    ) -> Bool {
        for decl in module.arena.declarations {
            guard case let .function(callerFn) = decl,
                  callerFn.symbol != lambdaSymbol
            else { continue }
            for instruction in callerFn.body {
                if case let .call(sym, callee, _, _, canThrow, _, _) = instruction,
                   (callee == lambdaName || sym == lambdaSymbol),
                   canThrow
                {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Phase 2: Synthesize closure object

    private func synthesizeClosureObject(
        lambdaInfo: LambdaCaptureInfo,
        module: KIRModule,
        ctx: KIRContext
    ) -> (invokeWrapperName: InternedString, declarations: [KIRDecl]) {
        let interner = ctx.interner
        let arena = module.arena
        let lambdaSymbolRaw = lambdaInfo.function.symbol.rawValue
        let intType = ctx.sema?.types.make(.primitive(.int, .nonNull))
            ?? TypeID(rawValue: 0)
        let anyType = ctx.sema?.types.anyType ?? TypeID(rawValue: 0)

        // Nominal type for the closure object.  Captures are stored in
        // object/array slots starting at offset 2 (not as KIR fields).
        let nominalSymbol: SymbolID
        if let sema = ctx.sema {
            let nominalName = interner.intern("kk_closure_obj_\(lambdaSymbolRaw)")
            nominalSymbol = sema.symbols.define(
                kind: .class,
                name: nominalName,
                fqName: [nominalName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        } else {
            nominalSymbol = SymbolID(rawValue: -(10_000_000 + lambdaSymbolRaw))
        }
        let nominalDecl = KIRDecl.nominalType(KIRNominalType(symbol: nominalSymbol))

        // Invoke wrapper function.
        let invokeWrapperName = interner.intern("kk_closure_invoke_\(lambdaSymbolRaw)")
        let invokeSymbol: SymbolID
        if let sema = ctx.sema {
            invokeSymbol = sema.symbols.define(
                kind: .function,
                name: invokeWrapperName,
                fqName: [invokeWrapperName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        } else {
            invokeSymbol = SymbolID(rawValue: -(20_000_000 + lambdaSymbolRaw))
        }

        let closureObjParamSymbol = SymbolID(rawValue: -(30_000_000 + lambdaSymbolRaw))
        let closureObjParam = KIRParameter(symbol: closureObjParamSymbol, type: anyType)
        let invokeParams = [closureObjParam] + lambdaInfo.valueParams
        let returnType = lambdaInfo.function.returnType

        var invokeBody: [KIRInstruction] = [.beginBlock]
        let kk_array_get = interner.intern("kk_array_get_inbounds")

        let closureObjExpr = arena.appendExpr(.symbolRef(closureObjParamSymbol), type: anyType)
        invokeBody.append(.constValue(result: closureObjExpr, value: .symbolRef(closureObjParamSymbol)))

        var loadedCaptureExprs: [KIRExprID] = []
        for captureIndex in 0 ..< lambdaInfo.captureParamCount {
            let fieldOffset = Int64(captureIndex + 2)
            let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: intType)
            invokeBody.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))

            let captureType = lambdaInfo.captureParams[captureIndex].type
            // Temp ID from arena.expressions.count: unique within the arena's
            // monotonic counter.  See comment at callResultExpr for rationale.
            let loadedExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: captureType)
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

        // NOTE: Temp numbering uses arena.expressions.count. This couples IDs
        // to global arena state; a per-function temp allocator would be cleaner
        // but the current approach is safe because each appendExpr returns a
        // unique KIRExprID within the arena's monotonic counter.
        let callResultExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: returnType)
        // Propagate canThrow from call-site analysis so the invoke wrapper
        // preserves throwing semantics of the original lambda call.
        invokeBody.append(.call(
            symbol: lambdaInfo.function.symbol,
            callee: lambdaInfo.function.name,
            arguments: loadedCaptureExprs + valueParamExprs,
            result: callResultExpr,
            canThrow: lambdaInfo.canThrow,
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

        return (invokeWrapperName, [nominalDecl, invokeFuncDecl])
    }

    // MARK: - Phase 3: Rewrite call sites

    private func rewriteCallSites(
        function: KIRFunction,
        markerCallee: InternedString,
        loweredCallee: InternedString,
        captureInfoBySymbol: [SymbolID: LambdaCaptureInfo],
        captureInfoByName: [InternedString: LambdaCaptureInfo],
        invokeWrapperByLambdaSymbol: [SymbolID: InternedString],
        module: KIRModule,
        ctx: KIRContext
    ) -> KIRFunction {
        let interner = ctx.interner
        let arena = module.arena
        let intType = ctx.sema?.types.make(.primitive(.int, .nonNull))
            ?? TypeID(rawValue: 0)
        let anyType = ctx.sema?.types.anyType ?? TypeID(rawValue: 0)
        let kk_object_new = interner.intern("kk_object_new")
        let kk_array_set = interner.intern("kk_array_set")

        var updated = function
        var loweredBody: [KIRInstruction] = []
        loweredBody.reserveCapacity(function.body.count * 2)

        for instruction in function.body {
            switch instruction {
            case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall):
                if callee == markerCallee {
                    loweredBody.append(.call(
                        symbol: symbol,
                        callee: loweredCallee,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                    continue
                }

                let captureInfo: LambdaCaptureInfo?
                let invokeWrapper: InternedString?
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

                    // Temp ID from arena.expressions.count: unique within the
                    // arena's monotonic counter.  See Phase 2 comment for rationale.
                    let closureObjExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
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

                        // Temp ID: see Phase 2 comment for rationale.
                        let unusedResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kk_array_set,
                            arguments: [closureObjExpr, offsetExpr, captureArg],
                            result: unusedResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }

                    // Use nil symbol so codegen resolves the invoke wrapper by
                    // name instead of dispatching to the original lambda via its SymbolID.
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: invokeWrapper,
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
