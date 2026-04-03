import Foundation

/// ANNO-002: `@JvmOverloads` lowering pass.
///
/// Synthesizes receiver-compatible wrapper overloads for trailing default
/// parameters so Java-style callers can bind to concrete entrypoints without
/// using Kotlin default-argument calling conventions.
final class JvmOverloadsLoweringPass: LoweringPass {
    static let name = "JvmOverloadsLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard let sema = ctx.sema else {
            return false
        }
        return module.arena.declarations.contains { decl in
            guard case let .function(function) = decl else {
                return false
            }
            return overloadPlan(for: function, symbols: sema.symbols) != nil
        }
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let symbols = sema.symbols
        let arena = module.arena
        let unitType = sema.types.unitType
        let originalDecls = arena.declarations

        for decl in originalDecls {
            guard case let .function(function) = decl,
                  let plan = overloadPlan(for: function, symbols: symbols),
                  let functionInfo = symbols.symbol(function.symbol)
            else {
                continue
            }

            let originalSignature = plan.signature
            let receiverParamCount = function.params.count - originalSignature.parameterTypes.count
            let receiverParams = receiverParamCount > 0 ? Array(function.params.prefix(receiverParamCount)) : []
            let valueParams = Array(function.params.dropFirst(receiverParamCount))

            for keepCount in plan.keepParameterCounts {
                let wrapperParams = receiverParams + valueParams.prefix(keepCount)
                let wrapperFQName = functionInfo.fqName
                var wrapperFlags = functionInfo.flags
                wrapperFlags.insert(.synthetic)

                let wrapperSymbol = symbols.define(
                    kind: .function,
                    name: function.name,
                    fqName: wrapperFQName,
                    declSite: functionInfo.declSite,
                    visibility: functionInfo.visibility,
                    flags: wrapperFlags
                )
                guard wrapperSymbol != function.symbol else {
                    continue
                }

                if let parentSymbol = symbols.parentSymbol(for: function.symbol) {
                    symbols.setParentSymbol(parentSymbol, for: wrapperSymbol)
                }

                let keptParameterTypes = Array(originalSignature.parameterTypes.prefix(keepCount))
                let keptValueParameterSymbols = Array(originalSignature.valueParameterSymbols.prefix(keepCount))
                let keptVarargFlags = Array(originalSignature.valueParameterIsVararg.prefix(keepCount))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: originalSignature.receiverType,
                        parameterTypes: keptParameterTypes,
                        returnType: originalSignature.returnType,
                        isSuspend: originalSignature.isSuspend,
                        canThrow: originalSignature.canThrow,
                        valueParameterSymbols: keptValueParameterSymbols,
                        valueParameterHasDefaultValues: Array(repeating: false, count: keepCount),
                        valueParameterIsVararg: keptVarargFlags,
                        typeParameterSymbols: originalSignature.typeParameterSymbols,
                        reifiedTypeParameterIndices: originalSignature.reifiedTypeParameterIndices,
                        typeParameterUpperBounds: originalSignature.typeParameterUpperBounds,
                        typeParameterUpperBoundsList: originalSignature.typeParameterUpperBoundsList,
                        classTypeParameterCount: originalSignature.classTypeParameterCount
                    ),
                    for: wrapperSymbol
                )

                let annotations = symbols.annotations(for: function.symbol)
                if !annotations.isEmpty {
                    symbols.setAnnotations(annotations, for: wrapperSymbol)
                }

                let wrapperBody = buildWrapperBody(
                    wrapperParams: Array(wrapperParams),
                    originalFunction: function,
                    unitType: unitType,
                    arena: arena
                )

                _ = arena.appendDecl(.function(KIRFunction(
                    symbol: wrapperSymbol,
                    name: function.name,
                    params: Array(wrapperParams),
                    returnType: function.returnType,
                    body: wrapperBody,
                    isSuspend: function.isSuspend,
                    isInline: function.isInline,
                    isInlineOnly: function.isInlineOnly,
                    isTailrec: function.isTailrec,
                    sourceRange: function.sourceRange
                )))
            }
        }

        module.recordLowering(Self.name)
    }

    private func overloadPlan(
        for function: KIRFunction,
        symbols: SymbolTable
    ) -> (signature: FunctionSignature, keepParameterCounts: [Int])? {
        guard let signature = symbols.functionSignature(for: function.symbol),
              symbols.annotations(for: function.symbol).contains(where: {
                  KnownCompilerAnnotation.jvmOverloads.matches($0.annotationFQName)
              })
        else {
            return nil
        }

        let defaults = signature.valueParameterHasDefaultValues
        guard !defaults.isEmpty, defaults.contains(true) else {
            return nil
        }

        var trailingDefaultCount = 0
        for hasDefault in defaults.reversed() {
            if hasDefault {
                trailingDefaultCount += 1
            } else {
                break
            }
        }
        guard trailingDefaultCount > 0 else {
            return nil
        }

        let totalParameters = signature.parameterTypes.count
        let requiredCount = totalParameters - trailingDefaultCount
        let keepCounts = Array(Array(requiredCount..<totalParameters).reversed())
        guard !keepCounts.isEmpty else {
            return nil
        }
        return (signature, keepCounts)
    }

    private func buildWrapperBody(
        wrapperParams: [KIRParameter],
        originalFunction: KIRFunction,
        unitType: TypeID,
        arena: KIRArena
    ) -> [KIRInstruction] {
        var body: [KIRInstruction] = [.beginBlock]
        var forwardedArgs: [KIRExprID] = []

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
}
