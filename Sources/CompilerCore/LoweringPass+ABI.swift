import Foundation

final class ABILoweringPass: LoweringPass {
    static let name = "ABILowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let nonThrowingCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_add"),
            ctx.interner.intern("kk_op_sub"),
            ctx.interner.intern("kk_op_mul"),
            ctx.interner.intern("kk_op_div"),
            ctx.interner.intern("kk_op_eq"),
            ctx.interner.intern("kk_string_concat"),
            ctx.interner.intern("kk_when_select"),
            ctx.interner.intern("kk_for_lowered"),
            ctx.interner.intern("iterator"),
            ctx.interner.intern("hasNext"),
            ctx.interner.intern("next"),
            ctx.interner.intern("kk_property_access"),
            ctx.interner.intern("kk_lambda_invoke"),
            ctx.interner.intern("kk_println_any"),
            ctx.interner.intern("kk_coroutine_suspended"),
            ctx.interner.intern("kk_coroutine_continuation_new"),
            ctx.interner.intern("kk_coroutine_state_enter"),
            ctx.interner.intern("kk_coroutine_state_set_label"),
            ctx.interner.intern("kk_coroutine_state_exit"),
            ctx.interner.intern("kk_coroutine_state_set_spill"),
            ctx.interner.intern("kk_coroutine_state_get_spill"),
            ctx.interner.intern("kk_coroutine_state_set_completion"),
            ctx.interner.intern("kk_coroutine_state_get_completion"),
            ctx.interner.intern("kk_kxmini_run_blocking"),
            ctx.interner.intern("kk_kxmini_launch"),
            ctx.interner.intern("kk_kxmini_async"),
            ctx.interner.intern("kk_kxmini_async_await"),
            ctx.interner.intern("kk_kxmini_delay"),
            ctx.interner.intern("kk_array_new")
        ]
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, _, let thrownResult) = instruction else {
                    return instruction
                }
                return .call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    canThrow: !nonThrowingCallees.contains(callee),
                    thrownResult: thrownResult
                )
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}
