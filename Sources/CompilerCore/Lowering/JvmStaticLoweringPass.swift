import Foundation

/// ANNO-001: @JvmStatic lowering pass.
///
/// Rewrites companion-object members annotated with `@JvmStatic` into
/// class-level static-like wrappers:
/// - Synthesize a new wrapper function symbol under the enclosing class.
/// - Wrapper body materializes the companion singleton and forwards to
///   the original companion member.
/// - Existing KIR call sites targeting the companion member are rewritten
///   to call the wrapper symbol (receiver argument removed).
final class JvmStaticLoweringPass: LoweringPass {
    static let name = "JvmStaticLowering"

    private struct WrapperInfo {
        let symbol: SymbolID
        let name: InternedString
        let dropsReceiverArgumentAtCallSite: Bool
    }

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard let sema = ctx.sema else {
            return false
        }
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            if isJvmStaticCompanionMember(function.symbol, symbols: sema.symbols) {
                return true
            }
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let symbols = sema.symbols
        let arena = module.arena
        let unitType = sema.types.unitType

        var wrappersByOriginal: [SymbolID: WrapperInfo] = [:]
        var newDecls: [KIRDecl] = []

        // Snapshot declarations so we only inspect original functions.
        let originalDecls = arena.declarations
        for decl in originalDecls {
            guard case let .function(function) = decl else {
                continue
            }
            guard let companionSymbol = companionSymbolForJvmStaticMember(
                functionSymbol: function.symbol,
                symbols: symbols
            ),
                let ownerSymbol = symbols.parentSymbol(for: companionSymbol),
                let ownerInfo = symbols.symbol(ownerSymbol),
                let functionInfo = symbols.symbol(function.symbol),
                let signature = symbols.functionSignature(for: function.symbol),
                signature.receiverType != nil
            else {
                continue
            }

            let wrapperName = function.name
            let wrapperFQName = ownerInfo.fqName + [wrapperName]
            var wrapperFlags = functionInfo.flags
            wrapperFlags.insert(.synthetic)
            wrapperFlags.insert(.static)

            let hasExplicitReceiverParam = function.params.count == signature.parameterTypes.count + 1

            let wrapperSymbol = symbols.define(
                kind: .function,
                name: wrapperName,
                fqName: wrapperFQName,
                declSite: functionInfo.declSite,
                visibility: functionInfo.visibility,
                flags: wrapperFlags
            )
            guard wrapperSymbol != function.symbol else {
                continue
            }
            symbols.setParentSymbol(ownerSymbol, for: wrapperSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: signature.parameterTypes,
                    returnType: signature.returnType,
                    isSuspend: signature.isSuspend,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    typeParameterSymbols: signature.typeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                    typeParameterUpperBounds: signature.typeParameterUpperBounds,
                    classTypeParameterCount: signature.classTypeParameterCount
                ),
                for: wrapperSymbol
            )
            let annotations = symbols.annotations(for: function.symbol)
            if !annotations.isEmpty {
                symbols.setAnnotations(annotations, for: wrapperSymbol)
            }

            let wrapperParams = hasExplicitReceiverParam ? Array(function.params.dropFirst()) : function.params
            let wrapperBody = buildWrapperBody(
                wrapperParams: wrapperParams,
                originalFunction: function,
                companionSymbol: companionSymbol,
                companionReceiverType: signature.receiverType,
                unitType: unitType,
                arena: arena
            )
            let wrapperFunction = KIRFunction(
                symbol: wrapperSymbol,
                name: wrapperName,
                params: wrapperParams,
                returnType: function.returnType,
                body: wrapperBody,
                isSuspend: function.isSuspend,
                isInline: function.isInline,
                sourceRange: function.sourceRange
            )
            newDecls.append(.function(wrapperFunction))
            wrappersByOriginal[function.symbol] = WrapperInfo(
                symbol: wrapperSymbol,
                name: wrapperName,
                dropsReceiverArgumentAtCallSite: hasExplicitReceiverParam
            )
        }

        if !wrappersByOriginal.isEmpty {
            arena.transformFunctions { function in
                var updated = function
                updated.replaceBody(rewriteCalls(
                    in: function.body,
                    wrappersByOriginal: wrappersByOriginal
                ))
                return updated
            }
            for decl in newDecls {
                _ = arena.appendDecl(decl)
            }
        }

        module.recordLowering(Self.name)
    }

    private func isJvmStaticCompanionMember(_ symbol: SymbolID, symbols: SymbolTable) -> Bool {
        guard companionSymbolForJvmStaticMember(functionSymbol: symbol, symbols: symbols) != nil else {
            return false
        }
        return symbols.annotations(for: symbol).contains { ann in
            KnownCompilerAnnotation.jvmStatic.matches(ann.annotationFQName)
        }
    }

    private func companionSymbolForJvmStaticMember(
        functionSymbol: SymbolID,
        symbols: SymbolTable
    ) -> SymbolID? {
        guard let parentSymbol = symbols.parentSymbol(for: functionSymbol),
              let parentInfo = symbols.symbol(parentSymbol),
              parentInfo.kind == .object,
              let ownerSymbol = symbols.parentSymbol(for: parentSymbol),
              let ownerInfo = symbols.symbol(ownerSymbol)
        else {
            return nil
        }
        guard ownerInfo.kind == .class || ownerInfo.kind == .interface else {
            return nil
        }
        guard symbols.companionObjectSymbol(for: ownerSymbol) == parentSymbol else {
            return nil
        }
        return parentSymbol
    }

    private func buildWrapperBody(
        wrapperParams: [KIRParameter],
        originalFunction: KIRFunction,
        companionSymbol: SymbolID,
        companionReceiverType: TypeID?,
        unitType: TypeID,
        arena: KIRArena
    ) -> [KIRInstruction] {
        var body: [KIRInstruction] = [.beginBlock]
        var forwardedArgs: [KIRExprID] = []

        if let receiverType = companionReceiverType {
            let receiverExpr = arena.appendExpr(.symbolRef(companionSymbol), type: receiverType)
            body.append(.constValue(result: receiverExpr, value: .symbolRef(companionSymbol)))
            forwardedArgs.append(receiverExpr)
        }

        for param in wrapperParams {
            let expr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: expr, value: .symbolRef(param.symbol)))
            forwardedArgs.append(expr)
        }

        if originalFunction.returnType == unitType {
            body.append(.call(
                symbol: originalFunction.symbol,
                callee: originalFunction.name,
                arguments: forwardedArgs,
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.returnUnit)
        } else {
            let callResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: originalFunction.returnType
            )
            body.append(.call(
                symbol: originalFunction.symbol,
                callee: originalFunction.name,
                arguments: forwardedArgs,
                result: callResult,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.returnValue(callResult))
        }

        body.append(.endBlock)
        return body
    }

    private func rewriteCalls(
        in body: [KIRInstruction],
        wrappersByOriginal: [SymbolID: WrapperInfo]
    ) -> [KIRInstruction] {
        body.map { instruction in
            switch instruction {
            case let .call(symbol, callee: _, arguments, result, canThrow, thrownResult, isSuperCall):
                guard let symbol, let wrapper = wrappersByOriginal[symbol] else {
                    return instruction
                }
                var rewrittenArgs = arguments
                if wrapper.dropsReceiverArgumentAtCallSite, !rewrittenArgs.isEmpty {
                    rewrittenArgs.removeFirst()
                }
                return .call(
                    symbol: wrapper.symbol,
                    callee: wrapper.name,
                    arguments: rewrittenArgs,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall
                )

            case let .virtualCall(symbol, callee: _, receiver: _, arguments, result, canThrow, thrownResult, dispatch: _):
                guard let symbol, let wrapper = wrappersByOriginal[symbol] else {
                    return instruction
                }
                return .call(
                    symbol: wrapper.symbol,
                    callee: wrapper.name,
                    arguments: arguments,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                )

            default:
                return instruction
            }
        }
    }
}
