import Foundation

/// Label base for tailrec loop-head labels, chosen to avoid collision
/// with user labels and coroutine dispatch labels.
let tailrecLoopLabelBase: Int32 = 9000

final class TailrecLoweringPass: LoweringPass {
    static let name = "TailrecLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        for decl in module.arena.declarations {
            if case let .function(function) = decl, function.isTailrec {
                return true
            }
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        var nextLoopLabel = tailrecLoopLabelBase

        module.arena.transformFunctions { function in
            guard function.isTailrec else { return function }

            let loopLabel = nextLoopLabel
            nextLoopLabel += 1

            var updated = function
            updated.body = rewriteTailCalls(
                body: function.body,
                functionSymbol: function.symbol,
                functionName: function.name,
                params: function.params,
                loopLabel: loopLabel,
                arena: module.arena,
                interner: ctx.interner
            )
            return updated
        }

        module.recordLowering(Self.name)
    }

    /// Rewrite a tailrec function body:
    /// 1. Insert a loop-head label after `beginBlock`.
    /// 2. Replace `call(self, args) + returnValue(result)` with
    ///    parameter reassignment (`copy`) + `jump(loopLabel)`.
    private func rewriteTailCalls(
        body: [KIRInstruction],
        functionSymbol: SymbolID,
        functionName: InternedString,
        params: [KIRParameter],
        loopLabel: Int32,
        arena: KIRArena,
        interner: StringInterner
    ) -> [KIRInstruction] {
        var result: [KIRInstruction] = []
        result.reserveCapacity(body.count + 2)

        var i = 0
        while i < body.count {
            let instruction = body[i]

            // Insert loop-head label right after beginBlock.
            if case .beginBlock = instruction {
                result.append(instruction)
                result.append(.label(loopLabel))
                i += 1
                continue
            }

            // Detect: call(self, args) → result, followed by returnValue(result).
            if case let .call(symbol, callee, arguments, callResult, _, _, _) = instruction,
               isSelfRecursiveCall(symbol: symbol, callee: callee, functionSymbol: functionSymbol, functionName: functionName),
               i + 1 < body.count,
               isReturnOfResult(body[i + 1], callResult: callResult)
            {
                // Emit parameter reassignment.
                emitParameterReassignment(
                    arguments: arguments,
                    params: params,
                    arena: arena,
                    result: &result
                )
                // Jump back to loop head.
                result.append(.jump(loopLabel))
                i += 2 // Skip both the call and the returnValue.
                continue
            }

            // Detect: call(self, args) with no result, followed by returnUnit.
            if case let .call(symbol, callee, arguments, nil, _, _, _) = instruction,
               isSelfRecursiveCall(symbol: symbol, callee: callee, functionSymbol: functionSymbol, functionName: functionName),
               i + 1 < body.count,
               case .returnUnit = body[i + 1]
            {
                emitParameterReassignment(
                    arguments: arguments,
                    params: params,
                    arena: arena,
                    result: &result
                )
                result.append(.jump(loopLabel))
                i += 2
                continue
            }

            result.append(instruction)
            i += 1
        }

        return result
    }

    /// Check if a call instruction targets the function being optimized.
    private func isSelfRecursiveCall(
        symbol: SymbolID?,
        callee: InternedString,
        functionSymbol: SymbolID,
        functionName: InternedString
    ) -> Bool {
        // Prefer matching by symbol when available (more precise).
        if let symbol, symbol == functionSymbol {
            return true
        }
        // Fall back to name matching for cases where symbol is nil.
        return callee == functionName
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

    /// Emit `copy` instructions to reassign the function parameters from
    /// the recursive call arguments.
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
            let temp = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            result.append(.copy(from: arg, to: temp))
            temporaries.append(temp)
        }

        // Then, assign temporaries to parameter symbol refs.
        for (index, param) in params.enumerated() {
            guard index < temporaries.count else { break }
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol))
            result.append(.copy(from: temporaries[index], to: paramExpr))
        }
    }
}
