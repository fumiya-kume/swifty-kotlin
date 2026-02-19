import Foundation

extension LLVMBackend {
    func ensureDeclared(_ id: KIRExprID, declared: inout Set<Int32>, lines: inout [String]) {
        guard declared.insert(id.rawValue).inserted else {
            return
        }
        lines.append("  intptr_t \(varName(id)) = 0;")
    }

    func varName(_ id: KIRExprID) -> String {
        "r\(id.rawValue)"
    }

    func labelName(_ id: Int32) -> String {
        "L\(max(0, id))"
    }

    func valueExpr(
        _ value: KIRExprKind,
        interner: StringInterner,
        functionSymbols: [SymbolID: String],
        globalValueSymbols: [SymbolID: String]
    ) -> String {
        switch value {
        case .intLiteral(let number):
            return "\(number)"
        case .longLiteral(let number):
            return "\(number)"
        case .floatLiteral(let value):
            return "kk_float_to_bits(\(formatCFloat(value))f)"
        case .doubleLiteral(let value):
            return "kk_double_to_bits(\(formatCDouble(value)))"
        case .charLiteral(let scalar):
            return "\(scalar)"
        case .boolLiteral(let bool):
            return bool ? "1" : "0"
        case .stringLiteral(let interned):
            let text = interner.resolve(interned)
            let escaped = cStringLiteral(text)
            let byteCount = text.utf8.count
            return "(intptr_t)kk_string_from_utf8((const uint8_t*)\(escaped), \(byteCount))"
        case .symbolRef(let symbol):
            if let functionSymbol = functionSymbols[symbol] {
                return "(intptr_t)\(functionSymbol)"
            }
            if let globalSymbol = globalValueSymbols[symbol] {
                return globalSymbol
            }
            return "0"
        case .temporary(let index):
            return "\(index)"
        case .null:
            return "KK_NULL_SENTINEL"
        case .unit:
            return "0"
        }
    }

    func globalSlotSymbol(for symbol: SymbolID) -> String {
        "kk_global_root_slot_\(max(0, Int(symbol.rawValue)))"
    }

    static func fpOpSymbol(_ calleeName: String) -> String {
        if calleeName.hasSuffix("add") { return "+" }
        if calleeName.hasSuffix("sub") { return "-" }
        if calleeName.hasSuffix("mul") { return "*" }
        if calleeName.hasSuffix("div") { return "/" }
        if calleeName.hasSuffix("mod") { return "%" }
        if calleeName.hasSuffix("eq") { return "==" }
        if calleeName.hasSuffix("ne") { return "!=" }
        if calleeName.hasSuffix("lt") { return "<" }
        if calleeName.hasSuffix("le") { return "<=" }
        if calleeName.hasSuffix("gt") { return ">" }
        if calleeName.hasSuffix("ge") { return ">=" }
        return "+"
    }

    func formatCFloat(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", value)
        }
        return "\(value)"
    }

    func formatCDouble(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", value)
        }
        return "\(value)"
    }

    func cStringLiteral(_ value: String) -> String {
        var escaped = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\":
                escaped += "\\\\"
            case "\"":
                escaped += "\\\""
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            case "\t":
                escaped += "\\t"
            default:
                escaped += String(scalar)
            }
        }
        escaped += "\""
        return escaped
    }

    static func sanitizeForCSymbol(_ text: String) -> String {
        if text.isEmpty {
            return "_"
        }
        var result = ""
        for (index, scalar) in text.unicodeScalars.enumerated() {
            let isAlphaNum = CharacterSet.alphanumerics.contains(scalar)
            if index == 0 {
                if CharacterSet.letters.contains(scalar) || scalar == "_" {
                    result.append(Character(scalar))
                } else if isAlphaNum {
                    result.append("_")
                    result.append(Character(scalar))
                } else {
                    result.append("_")
                }
            } else if isAlphaNum || scalar == "_" {
                result.append(Character(scalar))
            } else {
                result.append("_")
            }
        }
        if result.isEmpty {
            return "_"
        }
        return result
    }
}
