// swiftlint:disable trailing_comma

// MARK: - Builtin Operator Tables

extension LLVMBackend {
    static let builtinOps: [String: String] = [
        "kk_op_add": "+",
        "kk_op_sub": "-",
        "kk_op_mul": "*",
        "kk_op_div": "/",
        "kk_op_mod": "%",
        "kk_op_udiv": "/",
        "kk_op_urem": "%",
        "kk_op_ult": "<",
        "kk_op_ule": "<=",
        "kk_op_ugt": ">",
        "kk_op_uge": ">=",
        "kk_op_eq": "==",
        "kk_op_ne": "!=",
        "kk_op_lt": "<",
        "kk_op_le": "<=",
        "kk_op_gt": ">",
        "kk_op_ge": ">=",
        "kk_op_and": "&&",
        "kk_op_or": "||",
        // Bitwise/shift (P5-103)
        "kk_bitwise_and": "&",
        "kk_bitwise_or": "|",
        "kk_bitwise_xor": "^",
        "kk_op_shl": "<<",
        "kk_op_shr": ">>",
    ]

    /// Unary builtin ops: function name → C prefix operator (P5-103)
    static let unaryBuiltinOps: [String: String] = [
        "kk_op_not": "!",
        "kk_op_uplus": "+",
        "kk_op_uminus": "-",
        "kk_op_inv": "~",
    ]

    static let floatBuiltinOps: Set<String> = [
        "kk_op_fadd", "kk_op_fsub", "kk_op_fmul", "kk_op_fdiv", "kk_op_fmod",
        "kk_op_feq", "kk_op_fne", "kk_op_flt", "kk_op_fle", "kk_op_fgt", "kk_op_fge",
    ]

    static let doubleBuiltinOps: Set<String> = [
        "kk_op_dadd", "kk_op_dsub", "kk_op_dmul", "kk_op_ddiv", "kk_op_dmod",
        "kk_op_deq", "kk_op_dne", "kk_op_dlt", "kk_op_dle", "kk_op_dgt", "kk_op_dge",
    ]

    /// Returns `true` when `calleeName` refers to a built-in operator that the
    /// C backend inlines directly, meaning it should NOT be listed as an
    /// external callee declaration.
    static let unsignedBuiltinOps: Set<String> = [
        "kk_op_udiv", "kk_op_urem", "kk_op_ult", "kk_op_ule", "kk_op_ugt", "kk_op_uge",
    ]

    static func isBuiltinOp(_ calleeName: String) -> Bool {
        builtinOps[calleeName] != nil
            || unaryBuiltinOps[calleeName] != nil
            || calleeName == "kk_op_ushr"
            || unsignedBuiltinOps.contains(calleeName)
            || floatBuiltinOps.contains(calleeName)
            || doubleBuiltinOps.contains(calleeName)
    }
}

// swiftlint:enable trailing_comma

// MARK: - Symbol & Prototype Helpers

extension LLVMBackend {
    public static func cFunctionSymbol(for function: KIRFunction, interner: StringInterner) -> String {
        let rawName = interner.resolve(function.name)
        let safeName = sanitizeForCSymbol(rawName)
        let suffix = abs(function.symbol.rawValue)
        return "kk_fn_\(safeName)_\(suffix)"
    }

    func targetTripleString() -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }

    func functionPrototype(function: KIRFunction, interner: StringInterner) -> String {
        let symbol = Self.cFunctionSymbol(for: function, interner: interner)
        var parameters = function.params.indices.map { index in
            "intptr_t p\(index)"
        }
        parameters.append("intptr_t* outThrown")
        let joined = parameters.joined(separator: ", ")
        return "intptr_t \(symbol)(\(joined))"
    }
}
