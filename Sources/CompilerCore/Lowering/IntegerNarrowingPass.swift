import Foundation

/// Enforces Kotlin's 32-bit `Int` arithmetic semantics.
///
/// All runtime values in KSwiftK are stored in uniform 64-bit slots, so the
/// integer arithmetic / bitwise / shift builtins lowered by earlier passes
/// (`kk_op_add`, `kk_op_shl`, …) compute in 64 bits and never wrap at the
/// 32-bit boundary. Kotlin specifies that `Int` operations overflow using
/// two's-complement wraparound (e.g. `Int.MAX_VALUE + 1 == Int.MIN_VALUE`)
/// and that the shift operators use only the low five bits of the shift
/// distance (`1 shl 32 == 1`).
///
/// This pass runs late (just before ``ABILoweringPass``) and, for every
/// integer-result builtin whose result type is `Int`, restores the correct
/// 32-bit semantics:
///
/// * arithmetic / bitwise / unary builtins keep their operation but have the
///   result funneled through a `kk_int_narrow` builtin that sign-extends the
///   low 32 bits;
/// * the shift builtins are rewritten to width-aware variants
///   (`kk_op_ishl` / `kk_op_ishr` / `kk_op_iushr`) that mask the shift distance
///   and narrow the result.
///
/// `Long` results keep the 64-bit builtins untouched, and unsigned / floating
/// builtins are never matched, so their behavior is unchanged.
final class IntegerNarrowingPass: LoweringPass {
    static let name = "IntegerNarrowing"

    /// Binary / unary integer builtins whose `Int` result must wrap to 32 bits.
    /// `Long` variants (`kk_op_lmod`, `kk_op_lfloor_div`, …) are intentionally
    /// excluded because their result type is `Long` and they are already
    /// correct in 64 bits.
    private static let narrowingCalleeNames: Set<String> = [
        "kk_op_add", "kk_op_sub", "kk_op_mul", "kk_op_div",
        "kk_op_mod", "kk_op_floor_div", "kk_op_floor_mod",
        "kk_bitwise_and", "kk_bitwise_or", "kk_bitwise_xor",
        "kk_op_inv", "kk_op_uminus",
    ]

    /// Shift builtins rewritten to width-aware variants based on the result type.
    /// `Int` results use 32-bit variants (mask 5 bits + narrow); `Long` results
    /// use 64-bit variants (mask 6 bits) so that distances >= 64 are well defined.
    private static let intShiftRenameNames: [String: String] = [
        "kk_op_shl": "kk_op_ishl",
        "kk_op_shr": "kk_op_ishr",
        "kk_op_ushr": "kk_op_iushr",
    ]

    private static let longShiftRenameNames: [String: String] = [
        "kk_op_shl": "kk_op_lshl",
        "kk_op_shr": "kk_op_lshr",
        "kk_op_ushr": "kk_op_lushr",
    ]

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard ctx.sema != nil else { return false }
        let narrowingIDs = Set(Self.narrowingCalleeNames.map { ctx.interner.intern($0) })
        let shiftIDs = Set(Self.intShiftRenameNames.keys.map { ctx.interner.intern($0) })
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { continue }
                if narrowingIDs.contains(callee) || shiftIDs.contains(callee) {
                    return true
                }
            }
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let types = ctx.sema?.types else {
            module.recordLowering(Self.name)
            return
        }
        let interner = ctx.interner
        let arena = module.arena
        let narrowCallee = interner.intern("kk_int_narrow")
        let narrowingIDs = Set(Self.narrowingCalleeNames.map { interner.intern($0) })
        let intShiftRenameIDs: [InternedString: InternedString] = Dictionary(
            uniqueKeysWithValues: Self.intShiftRenameNames.map { (interner.intern($0.key), interner.intern($0.value)) }
        )
        let longShiftRenameIDs: [InternedString: InternedString] = Dictionary(
            uniqueKeysWithValues: Self.longShiftRenameNames.map { (interner.intern($0.key), interner.intern($0.value)) }
        )

        func resultPrimitive(_ result: KIRExprID?) -> PrimitiveType? {
            guard let result, let typeID = arena.exprType(result),
                  case let .primitive(primitive, _) = types.kind(of: typeID)
            else {
                return nil
            }
            return primitive
        }

        module.arena.transformFunctions { function in
            var updated = function
            var newBody: [KIRInstruction] = []
            newBody.reserveCapacity(function.body.count)
            for instruction in function.body {
                guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType) = instruction else {
                    newBody.append(instruction)
                    continue
                }

                let resultKind = resultPrimitive(result)

                // Shift operators: route shifts through width-aware variants that
                // mask the shift distance (5 bits for Int, 6 bits for Long) and,
                // for Int, narrow the result to 32 bits.
                if resultKind == .int, let renamed = intShiftRenameIDs[callee] {
                    newBody.append(.call(
                        symbol: symbol, callee: renamed, arguments: arguments, result: result,
                        canThrow: canThrow, thrownResult: thrownResult,
                        isSuperCall: isSuperCall, qualifiedSuperType: qualifiedSuperType
                    ))
                    continue
                }
                if resultKind == .long, let renamed = longShiftRenameIDs[callee] {
                    newBody.append(.call(
                        symbol: symbol, callee: renamed, arguments: arguments, result: result,
                        canThrow: canThrow, thrownResult: thrownResult,
                        isSuperCall: isSuperCall, qualifiedSuperType: qualifiedSuperType
                    ))
                    continue
                }

                // Arithmetic / bitwise / unary builtins: keep the operation but
                // wrap its Int result to 32 bits via kk_int_narrow.
                if narrowingIDs.contains(callee), let result, resultKind == .int {
                    let resultType = arena.exprType(result) ?? types.intType
                    let rawResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
                    newBody.append(.call(
                        symbol: symbol, callee: callee, arguments: arguments, result: rawResult,
                        canThrow: canThrow, thrownResult: thrownResult,
                        isSuperCall: isSuperCall, qualifiedSuperType: qualifiedSuperType
                    ))
                    newBody.append(.call(
                        symbol: nil, callee: narrowCallee, arguments: [rawResult], result: result,
                        canThrow: false, thrownResult: nil
                    ))
                    continue
                }

                newBody.append(instruction)
            }
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }
}
