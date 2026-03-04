// swiftlint:disable trailing_comma

// MARK: - Ignored External Callees

extension LLVMBackend {
    static let ignoredExternalCallees: Set<String> = [
        "println",
        "kk_println_any",
        "kk_string_concat",
        "kk_string_compareTo",
        "kk_string_length",
        "kk_any_to_string",
        "kk_string_from_utf8",
        "kk_op_is",

        "kk_coroutine_suspended",
        "kk_coroutine_continuation_new",
        "kk_coroutine_state_enter",
        "kk_coroutine_state_set_label",
        "kk_coroutine_state_exit",
        "kk_coroutine_state_set_spill",
        "kk_coroutine_state_get_spill",
        "kk_coroutine_state_set_completion",
        "kk_coroutine_state_get_completion",
        "kk_register_global_root",
        "kk_unregister_global_root",
        "kk_register_coroutine_root",
        "kk_unregister_coroutine_root",
        "kk_kxmini_run_blocking",
        "kk_kxmini_launch",
        "kk_kxmini_async",
        "kk_kxmini_async_await",
        "kk_kxmini_delay",
        "kk_flow_create",
        "kk_flow_emit",
        "kk_flow_collect",
        // CORO-002: Cancellation ABI
        "kk_coroutine_check_cancellation",
        "kk_is_cancellation_exception",
        "kk_job_cancel",
        "kk_coroutine_cancel",
        "kk_array_new",
        "kk_array_get",
        "kk_array_set",
        "kk_vararg_spread_concat",
        "kk_println_long",
        "kk_println_float",
        "kk_println_double",
        "kk_println_char",
        "kk_box_long",
        "kk_box_float",
        "kk_box_double",
        "kk_box_char",
        "kk_unbox_long",
        "kk_unbox_float",
        "kk_unbox_double",
        "kk_unbox_char",
        "kk_int_to_float_bits",
        "kk_int_to_double_bits",
        "kk_float_to_double_bits",
        "delay",
        "kk_op_notnull",
        "kk_op_elvis",
        "kk_op_cast",
        "kk_op_safe_cast",
        "kk_op_contains",
        "kk_object_new",
        "kk_type_register_super",
        "kk_type_register_iface",
        "kk_lazy_create",
        "kk_lazy_get_value",
        "kk_lazy_is_initialized",
        "kk_observable_create",
        "kk_observable_get_value",
        "kk_observable_set_value",
        "kk_vetoable_create",
        "kk_vetoable_get_value",
        "kk_vetoable_set_value",
        // Bitwise/shift (P5-103)
        "kk_bitwise_and",
        "kk_bitwise_or",
        "kk_bitwise_xor",
        "kk_op_inv",
        "kk_op_shl",
        "kk_op_shr",
        "kk_op_ushr",
        "kk_int_toString_radix",
        // Collection (STDLIB-001)
        "kk_list_of",
        "kk_list_size",
        "kk_list_get",
        "kk_list_contains",
        "kk_list_is_empty",
        "kk_list_iterator",
        "kk_list_iterator_hasNext",
        "kk_list_iterator_next",
        "kk_list_to_string",
        "kk_map_of",
        "kk_map_size",
        "kk_map_get",
        "kk_map_contains_key",
        "kk_map_is_empty",
        "kk_map_to_string",
        "kk_map_iterator",
        "kk_map_iterator_hasNext",
        "kk_map_iterator_next",
        "kk_array_size",
        "kk_array_of",
        // Higher-order collection functions (FUNC-003)
        "kk_list_map",
        "kk_list_filter",
        "kk_list_forEach",
        "kk_list_flatMap",
        "kk_list_any",
        "kk_list_none",
        "kk_list_all",
        // Sequence (STDLIB-003)
        "kk_sequence_from_list",
        "kk_sequence_map",
        "kk_sequence_filter",
        "kk_sequence_take",
        "kk_sequence_to_list",
        "kk_sequence_builder_create",
        "kk_sequence_builder_yield",
        "kk_sequence_builder_build",
        // Builder DSL (STDLIB-002)
        "kk_build_string",
        "kk_build_list",
        "kk_build_map",
        "kk_string_builder_append",
        "kk_mutable_list_add",
        "kk_mutable_map_put",
    ]

    func collectExternalCallees(
        module: KIRModule,
        interner: StringInterner,
        functionSymbols: [SymbolID: String]
    ) -> [String] {
        var callees: Set<String> = []

        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            for instruction in function.body {
                let calleeInfo: (symbol: SymbolID?, callee: InternedString)? = switch instruction {
                case let .call(symbol, callee, _, _, _, _, _):
                    (symbol, callee)
                case let .virtualCall(symbol, callee, _, _, _, _, _, _):
                    (symbol, callee)
                default:
                    nil
                }
                guard let calleeInfo else {
                    continue
                }
                if let symbol = calleeInfo.symbol, functionSymbols[symbol] != nil {
                    continue
                }

                let calleeName = interner.resolve(calleeInfo.callee)
                guard !calleeName.isEmpty,
                      !Self.isBuiltinOp(calleeName),
                      !Self.ignoredExternalCallees.contains(calleeName)
                else {
                    continue
                }
                callees.insert(calleeName)
            }
        }

        return callees.sorted()
    }

    func clangTargetArgs() -> [String] {
        var triple = "\(target.arch)-\(target.vendor)-\(target.os)"
        if let version = target.osVersion, !version.isEmpty {
            triple += version
        }
        return ["-target", triple]
    }

    func reportBackendError(code: String, message: String, error: CommandRunnerError) {
        switch error {
        case let .launchFailed(reason):
            diagnostics.error(code, "\(message). \(reason)", range: nil)
        case let .nonZeroExit(result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.isEmpty {
                diagnostics.error(code, "\(message). exit=\(result.exitCode)", range: nil)
            } else {
                diagnostics.error(code, "\(message). \(stderr)", range: nil)
            }
        }
    }
}

// swiftlint:enable trailing_comma
