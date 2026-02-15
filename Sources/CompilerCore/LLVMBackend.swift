import Foundation

public struct RuntimeLinkInfo {
    public let libraryPaths: [String]
    public let libraries: [String]
    public let extraObjects: [String]

    public init(libraryPaths: [String], libraries: [String], extraObjects: [String]) {
        self.libraryPaths = libraryPaths
        self.libraries = libraries
        self.extraObjects = extraObjects
    }
}

public final class LLVMBackend {
    private let target: TargetTriple
    private let optLevel: OptimizationLevel
    private let emitsDebugInfo: Bool
    private let diagnostics: DiagnosticEngine

    public init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        emitsDebugInfo: Bool,
        diagnostics: DiagnosticEngine
    ) {
        self.target = target
        self.optLevel = optLevel
        self.emitsDebugInfo = emitsDebugInfo
        self.diagnostics = diagnostics
    }

    public func emitObject(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputObjectPath: String,
        interner: StringInterner
    ) throws {
        try compileWithClang(
            module: module, interner: interner,
            extraArgs: ["-c"],
            outputPath: outputObjectPath,
            errorCode: "KSWIFTK-BACKEND-0001",
            errorContext: "object output"
        )
    }

    public func emitLLVMIR(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputIRPath: String,
        interner: StringInterner
    ) throws {
        try compileWithClang(
            module: module, interner: interner,
            extraArgs: ["-S", "-emit-llvm"],
            outputPath: outputIRPath,
            errorCode: "KSWIFTK-BACKEND-0002",
            errorContext: "LLVM IR output"
        )
    }

    private func compileWithClang(
        module: KIRModule,
        interner: StringInterner,
        extraArgs: [String],
        outputPath: String,
        errorCode: String,
        errorContext: String
    ) throws {
        let source = renderCModule(module: module, interner: interner)
        let sourceURL = deterministicTempSourceURL(outputPath: outputPath)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        do {
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            var args = ["-x", "c", "-std=c11"] + extraArgs + [sourceURL.path, "-o", outputPath]
            args.append(contentsOf: clangTargetArgs())
            _ = try CommandRunner.run(executable: "/usr/bin/clang", arguments: args)
        } catch let error as CommandRunnerError {
            reportBackendError(
                code: errorCode,
                message: "clang failed while emitting \(errorContext): \(outputPath)",
                error: error
            )
            throw error
        } catch {
            diagnostics.error(
                errorCode,
                "Failed to emit \(errorContext): \(outputPath)",
                range: nil
            )
            throw error
        }
    }

    private func deterministicTempSourceURL(outputPath: String) -> URL {
        let key = stableFNV1a64Hex(outputPath)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk_codegen_\(key)")
            .appendingPathExtension("c")
    }

    private func stableFNV1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private static let builtinOps: [String: String] = [
        "kk_op_add": "+", "kk_op_sub": "-", "kk_op_mul": "*", "kk_op_div": "/", "kk_op_eq": "=="
    ]

    public static func cFunctionSymbol(for function: KIRFunction, interner: StringInterner) -> String {
        let rawName = interner.resolve(function.name)
        let safeName = sanitizeForCSymbol(rawName)
        let suffix = max(0, function.symbol.rawValue)
        return "kk_fn_\(safeName)_\(suffix)"
    }

    private func targetTripleString() -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }

    private func renderCModule(module: KIRModule, interner: StringInterner) -> String {
        let functionSymbols: [SymbolID: String] = module.arena.declarations.reduce(into: [:]) { acc, decl in
            guard case .function(let function) = decl else {
                return
            }
            acc[function.symbol] = Self.cFunctionSymbol(for: function, interner: interner)
        }
        let externalCallees = collectExternalCallees(module: module, interner: interner, functionSymbols: functionSymbols)

        var lines: [String] = [
            "#include <stdint.h>",
            "#include <stddef.h>",
            "#include <stdlib.h>",
            "#include <stdio.h>",
            "#include <string.h>",
            "",
            "/* Generated by KSwiftK synthetic backend */",
            "typedef struct { int32_t len; uint8_t* bytes; } KKString;",
            "typedef struct { uint32_t rootCount; const int32_t* rootOffsets; } KKFrameMapDescriptor;",
            "__attribute__((weak)) void kk_register_frame_map(uint32_t functionID, const void* mapPtr) {",
            "  (void)functionID;",
            "  (void)mapPtr;",
            "}",
            "__attribute__((weak)) void kk_push_frame(uint32_t functionID, void* frameBase) {",
            "  (void)functionID;",
            "  (void)frameBase;",
            "}",
            "__attribute__((weak)) void kk_pop_frame(void) {}",
            "",
            "static void* kk_string_from_utf8(const uint8_t* ptr, int32_t len) {",
            "  if (len < 0) len = 0;",
            "  KKString* s = (KKString*)malloc(sizeof(KKString));",
            "  if (!s) return NULL;",
            "  s->len = len;",
            "  s->bytes = NULL;",
            "  if (len > 0) {",
            "    s->bytes = (uint8_t*)malloc((size_t)len);",
            "    if (!s->bytes) { free(s); return NULL; }",
            "    memcpy(s->bytes, ptr, (size_t)len);",
            "  }",
            "  return (void*)s;",
            "}",
            "static void* kk_string_concat(void* a, void* b) {",
            "  KKString* lhs = (KKString*)a;",
            "  KKString* rhs = (KKString*)b;",
            "  int32_t l = lhs ? lhs->len : 0;",
            "  int32_t r = rhs ? rhs->len : 0;",
            "  int32_t n = l + r;",
            "  KKString* out = (KKString*)malloc(sizeof(KKString));",
            "  if (!out) return NULL;",
            "  out->len = n;",
            "  out->bytes = NULL;",
            "  if (n > 0) {",
            "    out->bytes = (uint8_t*)malloc((size_t)n);",
            "    if (!out->bytes) { free(out); return NULL; }",
            "    if (lhs && lhs->bytes && l > 0) memcpy(out->bytes, lhs->bytes, (size_t)l);",
            "    if (rhs && rhs->bytes && r > 0) memcpy(out->bytes + l, rhs->bytes, (size_t)r);",
            "  }",
            "  return (void*)out;",
            "}",
            "static void kk_println_any(intptr_t obj) {",
            "  if (obj == 0) { puts(\"null\"); return; }",
            "  if (obj > -(intptr_t)0x100000000LL && obj < (intptr_t)0x100000000LL) {",
            "    printf(\"%ld\\n\", (long)obj);",
            "    return;",
            "  }",
            "  KKString* s = (KKString*)(void*)obj;",
            "  if (!s) { puts(\"null\"); return; }",
            "  if (s->len < 0 || s->len > (1 << 20)) {",
            "    printf(\"%ld\\n\", (long)obj);",
            "    return;",
            "  }",
            "  if (s->len > 0 && !s->bytes) {",
            "    printf(\"%ld\\n\", (long)obj);",
            "    return;",
            "  }",
            "  if (s->bytes && s->len > 0) fwrite(s->bytes, 1, (size_t)s->len, stdout);",
            "  fputc('\\n', stdout);",
            "}",
            "static void* kk_coroutine_suspended(void) {",
            "  static int32_t token = 0;",
            "  return (void*)&token;",
            "}",
            "static intptr_t kk_coroutine_state_enter(intptr_t continuation, intptr_t functionId) {",
            "  (void)continuation;",
            "  (void)functionId;",
            "  return 0;",
            "}",
            "static intptr_t kk_coroutine_state_set_label(intptr_t continuation, intptr_t label) {",
            "  (void)continuation;",
            "  return label;",
            "}",
            "static intptr_t kk_coroutine_state_exit(intptr_t continuation, intptr_t value) {",
            "  (void)continuation;",
            "  return value;",
            "}",
            ""
        ]

        for callee in externalCallees {
            lines.append("extern intptr_t \(callee)();")
        }
        if !externalCallees.isEmpty {
            lines.append("")
        }

        for decl in module.arena.declarations {
            guard case .function(let function) = decl else {
                continue
            }
            let frameMapSymbol = frameMapDescriptorSymbol(for: function)
            lines.append("static const KKFrameMapDescriptor \(frameMapSymbol) = { 0u, NULL };")
        }
        lines.append("")

        for decl in module.arena.declarations {
            guard case .function(let function) = decl else {
                continue
            }
            lines.append(functionPrototype(function: function, interner: interner) + ";")
        }
        lines.append("")
        lines.append("int32_t kk_module_function_count(void) { return \(module.functionCount); }")
        lines.append("")

        for decl in module.arena.declarations {
            guard case .function(let function) = decl else {
                continue
            }
            lines.append(functionPrototype(function: function, interner: interner) + " {")
            lines.append(contentsOf: emitFunctionBody(function: function, interner: interner, arena: module.arena, functionSymbols: functionSymbols))
            lines.append("}")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func functionPrototype(function: KIRFunction, interner: StringInterner) -> String {
        let symbol = Self.cFunctionSymbol(for: function, interner: interner)
        var parameters = function.params.enumerated().map { index, _ in
            "intptr_t p\(index)"
        }
        parameters.append("intptr_t* outThrown")
        return "intptr_t \(symbol)(\(parameters.joined(separator: ", ")))"
    }

    private func emitFunctionBody(
        function: KIRFunction,
        interner: StringInterner,
        arena: KIRArena,
        functionSymbols: [SymbolID: String]
    ) -> [String] {
        var lines: [String] = []
        var declared: Set<Int32> = []
        var callIndex = 0
        let functionID = max(0, Int(function.symbol.rawValue))
        var parameterNameBySymbol: [SymbolID: String] = [:]
        for (index, parameter) in function.params.enumerated() {
            parameterNameBySymbol[parameter.symbol] = "p\(index)"
        }

        lines.append("  kk_register_frame_map(\(functionID)u, &\(frameMapDescriptorSymbol(for: function)));")
        lines.append("  kk_push_frame(\(functionID)u, NULL);")
        lines.append("  if (outThrown) { *outThrown = 0; }")

        for instruction in function.body {
            switch instruction {
            case .nop:
                lines.append("  /* nop */")

            case .beginBlock, .endBlock:
                continue

            case .label(let id):
                lines.append("\(labelName(id)):")

            case .jump(let target):
                lines.append("  goto \(labelName(target));")

            case .jumpIfEqual(let lhs, let rhs, let target):
                ensureDeclared(lhs, declared: &declared, lines: &lines)
                ensureDeclared(rhs, declared: &declared, lines: &lines)
                lines.append("  if (\(varName(lhs)) == \(varName(rhs))) goto \(labelName(target));")

            case .constValue(let result, let value):
                ensureDeclared(result, declared: &declared, lines: &lines)
                if case .symbolRef(let symbol) = value,
                   let parameterName = parameterNameBySymbol[symbol] {
                    lines.append("  \(varName(result)) = \(parameterName);")
                } else {
                    lines.append("  \(varName(result)) = \(valueExpr(value, interner: interner));")
                }

            case .binary(let op, let lhs, let rhs, let result):
                ensureDeclared(result, declared: &declared, lines: &lines)
                ensureDeclared(lhs, declared: &declared, lines: &lines)
                ensureDeclared(rhs, declared: &declared, lines: &lines)
                let opText: String
                switch op {
                case .add:
                    opText = "+"
                case .subtract:
                    opText = "-"
                case .multiply:
                    opText = "*"
                case .divide:
                    opText = "/"
                case .equal:
                    opText = "=="
                }
                lines.append("  \(varName(result)) = (\(varName(lhs)) \(opText) \(varName(rhs)));")

            case .call(let symbol, let callee, let arguments, let result, let usesThrownChannel):
                let calleeName = interner.resolve(callee)
                let argVars = arguments.map { arg -> String in
                    ensureDeclared(arg, declared: &declared, lines: &lines)
                    return varName(arg)
                }

                if let result {
                    ensureDeclared(result, declared: &declared, lines: &lines)
                }

                if calleeName == "println" || calleeName == "kk_println_any" {
                    let value = argVars.first ?? "0"
                    lines.append("  kk_println_any(\(value));")
                    if let result {
                        lines.append("  \(varName(result)) = 0;")
                    }
                    continue
                }

                if let cOp = LLVMBackend.builtinOps[calleeName] {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let expr = "(\(lhs) \(cOp) \(rhs))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if calleeName == "kk_string_concat" {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let expr = "(intptr_t)kk_string_concat((void*)\(lhs), (void*)\(rhs))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if calleeName == "kk_when_select" {
                    let condition = argVars.count > 0 ? argVars[0] : "0"
                    let thenValue = argVars.count > 1 ? argVars[1] : "0"
                    let elseValue = argVars.count > 2 ? argVars[2] : "0"
                    let value = "(\(condition) ? \(thenValue) : \(elseValue))"
                    if let result {
                        lines.append("  \(varName(result)) = \(value);")
                    } else {
                        lines.append("  (void)\(value);")
                    }
                    continue
                }

                let target: String
                let isInternalFunction: Bool
                if let symbol, let resolved = functionSymbols[symbol] {
                    target = resolved
                    isInternalFunction = true
                } else {
                    target = calleeName.isEmpty ? "0" : calleeName
                    isInternalFunction = false
                }
                var callArguments = argVars
                var thrownSlotName: String? = nil
                if usesThrownChannel {
                    let slot = "thrown_\(callIndex)"
                    callIndex += 1
                    lines.append("  intptr_t \(slot) = 0;")
                    thrownSlotName = slot
                    callArguments.append("&\(slot)")
                } else if isInternalFunction {
                    callArguments.append("NULL")
                }

                let callExpr = "\(target)(\(callArguments.joined(separator: ", ")))"
                if let result {
                    lines.append("  \(varName(result)) = \(callExpr);")
                } else {
                    lines.append("  (void)\(callExpr);")
                }
                if let thrownSlotName {
                    lines.append("  if (\(thrownSlotName) != 0) {")
                    lines.append("    if (outThrown) { *outThrown = \(thrownSlotName); }")
                    lines.append("    kk_pop_frame();")
                    lines.append("    return 0;")
                    lines.append("  }")
                }

            case .returnIfEqual(let lhs, let rhs):
                ensureDeclared(lhs, declared: &declared, lines: &lines)
                ensureDeclared(rhs, declared: &declared, lines: &lines)
                lines.append("  if (\(varName(lhs)) == \(varName(rhs))) {")
                lines.append("    kk_pop_frame();")
                lines.append("    return \(varName(lhs));")
                lines.append("  }")

            case .returnUnit:
                lines.append("  kk_pop_frame();")
                lines.append("  return 0;")

            case .returnValue(let value):
                ensureDeclared(value, declared: &declared, lines: &lines)
                lines.append("  kk_pop_frame();")
                lines.append("  return \(varName(value));")
            }
        }

        if lines.last?.hasPrefix("  return ") != true {
            lines.append("  kk_pop_frame();")
            lines.append("  return 0;")
        }
        return lines
    }

    private func frameMapDescriptorSymbol(for function: KIRFunction) -> String {
        "kk_frame_map_\(max(0, Int(function.symbol.rawValue)))"
    }

    private func ensureDeclared(_ id: KIRExprID, declared: inout Set<Int32>, lines: inout [String]) {
        guard declared.insert(id.rawValue).inserted else {
            return
        }
        lines.append("  intptr_t \(varName(id)) = 0;")
    }

    private func varName(_ id: KIRExprID) -> String {
        "r\(id.rawValue)"
    }

    private func labelName(_ id: Int32) -> String {
        "L\(max(0, id))"
    }

    private func valueExpr(_ value: KIRExprKind, interner: StringInterner) -> String {
        switch value {
        case .intLiteral(let number):
            return "\(number)"
        case .boolLiteral(let bool):
            return bool ? "1" : "0"
        case .stringLiteral(let interned):
            let text = interner.resolve(interned)
            let escaped = cStringLiteral(text)
            let byteCount = text.utf8.count
            return "(intptr_t)kk_string_from_utf8((const uint8_t*)\(escaped), \(byteCount))"
        case .symbolRef:
            return "0"
        case .temporary(let index):
            return "\(index)"
        case .unit:
            return "0"
        }
    }

    private func cStringLiteral(_ value: String) -> String {
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

    private static func sanitizeForCSymbol(_ text: String) -> String {
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

    private func collectExternalCallees(
        module: KIRModule,
        interner: StringInterner,
        functionSymbols: [SymbolID: String]
    ) -> [String] {
        var callees: Set<String> = []
        let ignored: Set<String> = [
            "println",
            "kk_println_any",
            "kk_string_concat",
            "kk_string_from_utf8",
            "kk_when_select",
            "kk_coroutine_suspended",
            "kk_coroutine_state_enter",
            "kk_coroutine_state_set_label",
            "kk_coroutine_state_exit"
        ]

        for decl in module.arena.declarations {
            guard case .function(let function) = decl else {
                continue
            }
            for instruction in function.body {
                guard case .call(let symbol, let callee, _, _, _) = instruction else {
                    continue
                }
                if let symbol, functionSymbols[symbol] != nil {
                    continue
                }

                let calleeName = interner.resolve(callee)
                guard !calleeName.isEmpty else {
                    continue
                }
                if LLVMBackend.builtinOps[calleeName] != nil {
                    continue
                }
                if ignored.contains(calleeName) {
                    continue
                }
                callees.insert(calleeName)
            }
        }

        return callees.sorted()
    }

    private func clangTargetArgs() -> [String] {
        var triple = "\(target.arch)-\(target.vendor)-\(target.os)"
        if let version = target.osVersion, !version.isEmpty {
            triple += version
        }
        return ["-target", triple]
    }

    private func reportBackendError(code: String, message: String, error: CommandRunnerError) {
        switch error {
        case .launchFailed(let reason):
            diagnostics.error(code, "\(message). \(reason)", range: nil)
        case .nonZeroExit(let result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.isEmpty {
                diagnostics.error(code, "\(message). exit=\(result.exitCode)", range: nil)
            } else {
                diagnostics.error(code, "\(message). \(stderr)", range: nil)
            }
        }
    }
}
