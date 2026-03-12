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

            // Avoid label collision: scan the function's existing labels and
            // ensure the generated loop-head label is strictly greater.
            let maxExistingLabel = function.body.compactMap { instruction -> Int32? in
                if case let .label(id) = instruction { return id }
                return nil
            }.max() ?? (tailrecLoopLabelBase - 1)

            let loopLabel = max(nextLoopLabel, maxExistingLabel + 1)
            nextLoopLabel = loopLabel + 1

            let functionIdentity = TailrecFunctionIdentity(
                symbol: function.symbol,
                name: function.name
            )
            var updated = function
            updated.replaceBody(rewriteTailCalls(
                body: function.body,
                functionIdentity: functionIdentity,
                params: function.params,
                loopLabel: loopLabel,
                arena: module.arena
            ))
            // Reset instructionLocations to match the new body length.
            // The rewrite changes instruction count, so the old parallel
            // array is stale.  Use the function-level sourceRange as a
            // conservative location for every synthesised instruction.
            updated.replaceInstructionLocations(Array(
                repeating: function.sourceRange,
                count: updated.body.count
            ))
            return updated
        }

        module.recordLowering(Self.name)
    }

    /// Rewrite a tailrec function body:
    /// 1. Insert a loop-head label at the start of the body (index 0).
    /// 2. Replace `call(self, args) + returnValue(result)` with
    ///    parameter reassignment (`copy`) + `jump(loopLabel)`.
    /// 3. Also handle Unit-returning tail calls (`call + returnUnit`).
    private func rewriteTailCalls(
        body: [KIRInstruction],
        functionIdentity: TailrecFunctionIdentity,
        params: [KIRParameter],
        loopLabel: Int32,
        arena: KIRArena
    ) -> [KIRInstruction] {
        var result: [KIRInstruction] = []
        result.reserveCapacity(body.count + 2)
        let loopInsertIndex = loopEntryIndex(body: body, params: params)
        let canonicalParamExprs = canonicalParameterExprs(
            body: Array(body[..<loopInsertIndex]),
            params: params
        )
        if loopInsertIndex > 0 {
            result.append(contentsOf: body[..<loopInsertIndex])
        }
        result.append(.label(loopLabel))

        var instructionIndex = loopInsertIndex
        var emittedTailJump = false
        while instructionIndex < body.count {
            let instruction = body[instructionIndex]

            // Skip beginBlock/endBlock — NormalizeBlocksPass may or may not
            // have removed these already; either way we don't need them for
            // the loop-head approach.
            if case .beginBlock = instruction {
                result.append(instruction)
                instructionIndex += 1
                continue
            }

            // --- Value-returning tail call: call(self, args) → result, then returnValue(result) ---
            if case let .call(symbol, _, arguments, callResult?, _, _, _) = instruction,
               isSelfRecursiveCall(symbol: symbol, functionIdentity: functionIdentity),
               instructionIndex + 1 < body.count,
               isReturnOfResult(body[instructionIndex + 1], callResult: callResult)
            {
                emitParameterReassignment(
                    arguments: arguments,
                    params: params,
                    canonicalParamExprs: canonicalParamExprs,
                    arena: arena,
                    result: &result
                )
                result.append(.jump(loopLabel))
                emittedTailJump = true
                instructionIndex += 2
                continue
            }

            // --- Unit-returning tail call: call(self, args, nil), then returnUnit ---
            if case let .call(symbol, _, arguments, nil, _, _, _) = instruction,
               isSelfRecursiveCall(symbol: symbol, functionIdentity: functionIdentity),
               instructionIndex + 1 < body.count,
               isReturnUnitInstruction(body[instructionIndex + 1])
            {
                emitParameterReassignment(
                    arguments: arguments,
                    params: params,
                    canonicalParamExprs: canonicalParamExprs,
                    arena: arena,
                    result: &result
                )
                result.append(.jump(loopLabel))
                emittedTailJump = true
                instructionIndex += 2
                continue
            }

            result.append(instruction)
            instructionIndex += 1
        }

        // Safety: if we emitted a jump but somehow the label is missing
        // (should not happen with the unconditional insert above), leave
        // the body unchanged to avoid producing invalid KIR.
        if emittedTailJump, !result.contains(where: { if case .label(loopLabel) = $0 { return true }; return false }) {
            return body
        }

        return result
    }

    /// Check if a call instruction targets the function being optimized.
    /// Only matches by symbol identity; name-only fallback is intentionally
    /// omitted to avoid misidentifying calls to different functions that
    /// share the same name (overloads, runtime helpers, etc.).
    private func isSelfRecursiveCall(
        symbol: SymbolID?,
        functionIdentity: TailrecFunctionIdentity
    ) -> Bool {
        guard let symbol else { return false }
        return symbol == functionIdentity.symbol
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
        canonicalParamExprs: [SymbolID: KIRExprID],
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
            let paramExpr = canonicalParamExprs[param.symbol]
                ?? arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            result.append(.copy(from: temporaries[index], to: paramExpr))
        }
    }

    private func canonicalParameterExprs(
        body: [KIRInstruction],
        params: [KIRParameter]
    ) -> [SymbolID: KIRExprID] {
        let parameterSymbols = Set(params.map(\.symbol))
        var result: [SymbolID: KIRExprID] = [:]
        for instruction in body {
            guard case let .constValue(exprID, .symbolRef(symbol)) = instruction,
                  parameterSymbols.contains(symbol),
                  result[symbol] == nil
            else {
                continue
            }
            result[symbol] = exprID
        }
        return result
    }

    private func loopEntryIndex(body: [KIRInstruction], params: [KIRParameter]) -> Int {
        let parameterSymbols = Set(params.map(\.symbol))
        var index = 0
        if index < body.count, case .beginBlock = body[index] {
            index += 1
        }
        while index < body.count {
            guard case let .constValue(_, .symbolRef(symbol)) = body[index],
                  parameterSymbols.contains(symbol)
            else {
                break
            }
            index += 1
        }
        return index
    }
}
