import Foundation

/// Label base for tailrec loop-head labels, chosen to avoid collision
/// with user labels and coroutine dispatch labels.
let tailrecLoopLabelBase: Int32 = 9000

final class TailrecLoweringPass: LoweringPass {
    static let name = "TailrecLowering"

    private struct TailrecFunctionIdentity {
        let symbol: SymbolID
        let name: InternedString
    }

    func shouldRun(module: KIRModule, ctx _: KIRContext) -> Bool {
        for decl in module.arena.declarations {
            if case let .function(function) = decl, function.isTailrec {
                return true
            }
        }
        return false
    }

    func run(module: KIRModule, ctx _: KIRContext) throws {
        var nextLoopLabel = tailrecLoopLabelBase

        module.arena.transformFunctions { function in
            guard function.isTailrec else { return function }

            let loopLabel = nextLoopLabel
            nextLoopLabel += 1

            let functionIdentity = TailrecFunctionIdentity(
                symbol: function.symbol,
                name: function.name
            )
            var updated = function
            updated.body = rewriteTailCalls(
                body: function.body,
                functionIdentity: functionIdentity,
                params: function.params,
                loopLabel: loopLabel,
                arena: module.arena
            )
            return updated
        }

        module.recordLowering(Self.name)
    }

    /// Rewrite a tailrec function body:
    /// 1. Insert a loop-head label after the first `beginBlock` only.
    /// 2. Replace `call(self, args) + returnValue(result)` with
    ///    parameter reassignment (`copy`) + `jump(loopLabel)`.
    private func rewriteTailCalls( // swiftlint:disable:this function_body_length
        body: [KIRInstruction],
        functionIdentity: TailrecFunctionIdentity,
        params: [KIRParameter],
        loopLabel: Int32,
        arena: KIRArena
    ) -> [KIRInstruction] {
        var result: [KIRInstruction] = []
        result.reserveCapacity(body.count + 2)

        var instructionIndex = 0
        var insertedLoopLabel = false
        while instructionIndex < body.count {
            let instruction = body[instructionIndex]

            // Insert loop-head label right after the first beginBlock only.
            if case .beginBlock = instruction, !insertedLoopLabel {
                result.append(instruction)
                result.append(.label(loopLabel))
                insertedLoopLabel = true
                instructionIndex += 1
                continue
            }

            // Detect: call(self, args) → result, followed by returnValue(result).
            if case let .call(symbol, callee, arguments, callResult, _, _, _) = instruction {
                let isSelfRecursive = isSelfRecursiveCall(
                    symbol: symbol,
                    callee: callee,
                    functionIdentity: functionIdentity
                )
                guard isSelfRecursive else {
                    result.append(instruction)
                    instructionIndex += 1
                    continue
                }
                let hasReturnOfCallResult = instructionIndex + 1 < body.count
                    && isReturnOfResult(
                        body[instructionIndex + 1],
                        callResult: callResult
                    )
                if hasReturnOfCallResult {
                    // Emit parameter reassignment.
                    emitParameterReassignment(
                        arguments: arguments,
                        params: params,
                        arena: arena,
                        result: &result
                    )
                    // Jump back to loop head.
                    result.append(.jump(loopLabel))
                    instructionIndex += 2 // Skip both the call and the returnValue.
                    continue
                }
                result.append(instruction)
                instructionIndex += 1
                continue
            }

            // Detect: call(self, args) with no result, followed by returnUnit.
            if case let .call(symbol, callee, arguments, nil, _, _, _) = instruction {
                let isSelfRecursive = isSelfRecursiveCall(
                    symbol: symbol,
                    callee: callee,
                    functionIdentity: functionIdentity
                )
                guard isSelfRecursive else {
                    result.append(instruction)
                    instructionIndex += 1
                    continue
                }
                let hasFollowingReturnUnit = instructionIndex + 1 < body.count
                    && isReturnUnitInstruction(body[instructionIndex + 1])
                if hasFollowingReturnUnit {
                    emitParameterReassignment(
                        arguments: arguments,
                        params: params,
                        arena: arena,
                        result: &result
                    )
                    result.append(.jump(loopLabel))
                    instructionIndex += 2
                    continue
                }
                result.append(instruction)
                instructionIndex += 1
                continue
            }

            result.append(instruction)
            instructionIndex += 1
        }

        return result
    }

    /// Check if a call instruction targets the function being optimized.
    private func isSelfRecursiveCall(
        symbol: SymbolID?,
        callee: InternedString,
        functionIdentity: TailrecFunctionIdentity
    ) -> Bool {
        // Prefer matching by symbol when available (more precise).
        if let symbol, symbol == functionIdentity.symbol {
            return true
        }
        // Fall back to name matching for cases where symbol is nil.
        return callee == functionIdentity.name
    }

    /// Check if the next instruction is `returnValue(r)` where `r` matches
    /// the call result.
    private func isReturnOfResult(
        _ instruction: KIRInstruction, callResult: KIRExprID?
    ) -> Bool {
        guard let callResult else { return false }
        if case let .returnValue(value) = instruction, value == callResult {
            return true
        }
        return false
    }

    private func isReturnUnitInstruction(_ instruction: KIRInstruction) -> Bool {
        if case .returnUnit = instruction {
            return true
        }
        return false
    }

    /// Emit `copy` instructions to reassign the function parameters from
    /// the recursive call arguments.  Also propagates expression types for
    /// the newly created temporaries and symbol refs.
    private func emitParameterReassignment(
        arguments: [KIRExprID],
        params: [KIRParameter],
        arena: KIRArena,
        result: inout [KIRInstruction]
    ) {
        // First, copy all arguments into fresh temporaries to avoid
        // overwriting a parameter that is used in a later argument expression.
        var temporaries: [KIRExprID] = []
        temporaries.reserveCapacity(arguments.count)
        for arg in arguments {
            let argType = arena.exprType(arg)
            let temp = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: argType)
            result.append(.copy(from: arg, to: temp))
            temporaries.append(temp)
        }

        // Then, assign temporaries to parameter symbol refs.
        for (index, param) in params.enumerated() {
            guard index < temporaries.count else { break }
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            result.append(.copy(from: temporaries[index], to: paramExpr))
        }
    }
}
