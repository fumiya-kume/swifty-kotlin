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
    private let debugInfo: Bool
    private let diagnostics: DiagnosticEngine

    public init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        diagnostics: DiagnosticEngine
    ) {
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.diagnostics = diagnostics
    }

    @available(*, deprecated, message: "Use init(target:optLevel:debugInfo:diagnostics:) instead.")
    public convenience init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        emitsDebugInfo: Bool,
        diagnostics: DiagnosticEngine
    ) {
        self.init(
            target: target,
            optLevel: optLevel,
            debugInfo: emitsDebugInfo,
            diagnostics: diagnostics
        )
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
        let source = emitCModule(module: module, interner: interner)
        let sourceURL = deterministicTempSourceURL(outputPath: outputPath)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        do {
            try source.write(to: sourceURL, atomically: false, encoding: .utf8)
            var args = ["-x", "c", "-std=c11"] + extraArgs
            if debugInfo {
                args.append("-g")
            }
            args.append(contentsOf: [sourceURL.path, "-o", outputPath])
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
        "kk_op_add": "+",
        "kk_op_sub": "-",
        "kk_op_mul": "*",
        "kk_op_div": "/",
        "kk_op_eq": "==",
        "kk_op_ne": "!=",
        "kk_op_lt": "<",
        "kk_op_le": "<=",
        "kk_op_gt": ">",
        "kk_op_ge": ">=",
        "kk_op_and": "&&",
        "kk_op_or": "||"
    ]

    private static let floatBuiltinOps: Set<String> = [
        "kk_op_fadd", "kk_op_fsub", "kk_op_fmul", "kk_op_fdiv", "kk_op_fmod",
        "kk_op_feq", "kk_op_fne", "kk_op_flt", "kk_op_fle", "kk_op_fgt", "kk_op_fge"
    ]

    private static let doubleBuiltinOps: Set<String> = [
        "kk_op_dadd", "kk_op_dsub", "kk_op_dmul", "kk_op_ddiv", "kk_op_dmod",
        "kk_op_deq", "kk_op_dne", "kk_op_dlt", "kk_op_dle", "kk_op_dgt", "kk_op_dge"
    ]

    private struct FrameMapPlan {
        let parameterSlotBySymbol: [SymbolID: Int]
        let exprSlotByID: [Int32: Int]
        let rootOffsets: [Int32]

        static let empty = FrameMapPlan(
            parameterSlotBySymbol: [:],
            exprSlotByID: [:],
            rootOffsets: []
        )

        var rootCount: Int {
            rootOffsets.count
        }
    }

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

    private func emitCModule(module: KIRModule, interner: StringInterner) -> String {
        let functions: [KIRFunction] = module.arena.declarations.compactMap { decl in
            guard case .function(let function) = decl else {
                return nil
            }
            return function
        }
        let globals: [KIRGlobal] = module.arena.declarations.compactMap { decl in
            guard case .global(let global) = decl else {
                return nil
            }
            return global
        }.sorted(by: { lhs, rhs in
            lhs.symbol.rawValue < rhs.symbol.rawValue
        })
        let globalValueSymbols: [SymbolID: String] = globals.reduce(into: [:]) { partial, global in
            partial[global.symbol] = globalSlotSymbol(for: global.symbol)
        }
        let functionSymbols: [SymbolID: String] = functions.reduce(into: [:]) { acc, function in
            acc[function.symbol] = Self.cFunctionSymbol(for: function, interner: interner)
        }
        let frameMapPlans: [SymbolID: FrameMapPlan] = functions.reduce(into: [:]) { plans, function in
            plans[function.symbol] = buildFrameMapPlan(function: function)
        }
        let externalCallees = collectExternalCallees(module: module, interner: interner, functionSymbols: functionSymbols)

        var lines: [String] = [
            "#include <stdint.h>",
            "#include <stddef.h>",
            "#include <stdlib.h>",
            "#include <stdio.h>",
            "#include <string.h>",
            "#include <unistd.h>",
            "#include <math.h>",
            "#define KK_NULL_SENTINEL ((intptr_t)INTPTR_MIN)",
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
            "__attribute__((weak)) void kk_register_global_root(void** slot) {",
            "  (void)slot;",
            "}",
            "__attribute__((weak)) void kk_unregister_global_root(void** slot) {",
            "  (void)slot;",
            "}",
            "__attribute__((weak)) void kk_register_coroutine_root(void* value) {",
            "  (void)value;",
            "}",
            "__attribute__((weak)) void kk_unregister_coroutine_root(void* value) {",
            "  (void)value;",
            "}",
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
            "  if ((intptr_t)a == KK_NULL_SENTINEL) a = NULL;",
            "  if ((intptr_t)b == KK_NULL_SENTINEL) b = NULL;",
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
            "typedef struct {",
            "  intptr_t length;",
            "  intptr_t* elements;",
            "} KKArray;",
            "static intptr_t kk_array_new(intptr_t length) {",
            "  if (length < 0) length = 0;",
            "  KKArray* array = (KKArray*)malloc(sizeof(KKArray));",
            "  if (!array) return 0;",
            "  array->length = length;",
            "  array->elements = NULL;",
            "  if (length > 0) {",
            "    array->elements = (intptr_t*)calloc((size_t)length, sizeof(intptr_t));",
            "    if (!array->elements) { free(array); return 0; }",
            "  }",
            "  return (intptr_t)array;",
            "}",
            "static intptr_t kk_array_get(intptr_t arrayRaw, intptr_t index, intptr_t* outThrown) {",
            "  if (outThrown) { *outThrown = 0; }",
            "  KKArray* array = (KKArray*)(void*)arrayRaw;",
            "  if (!array || index < 0 || index >= array->length) {",
            "    if (outThrown) { *outThrown = 1; }",
            "    return 0;",
            "  }",
            "  return array->elements[index];",
            "}",
            "static intptr_t kk_array_set(intptr_t arrayRaw, intptr_t index, intptr_t value, intptr_t* outThrown) {",
            "  if (outThrown) { *outThrown = 0; }",
            "  KKArray* array = (KKArray*)(void*)arrayRaw;",
            "  if (!array || index < 0 || index >= array->length) {",
            "    if (outThrown) { *outThrown = 1; }",
            "    return 0;",
            "  }",
            "  array->elements[index] = value;",
            "  return value;",
            "}",
            "typedef struct { intptr_t tag; intptr_t value; } KKBoxedValue;",
            "#define KK_BOX_TAG_INT    0x4B424F49",
            "#define KK_BOX_TAG_BOOL   0x4B424F42",
            "#define KK_BOX_TAG_LONG   0x4B424F4C",
            "#define KK_BOX_TAG_FLOAT  0x4B424F46",
            "#define KK_BOX_TAG_DOUBLE 0x4B424F44",
            "#define KK_BOX_TAG_CHAR   0x4B424F43",
            "static intptr_t kk_box_int(intptr_t value) {",
            "  if (value == KK_NULL_SENTINEL) return value;",
            "  KKBoxedValue* box = (KKBoxedValue*)malloc(sizeof(KKBoxedValue));",
            "  if (!box) return value;",
            "  box->tag = KK_BOX_TAG_INT;",
            "  box->value = value;",
            "  return (intptr_t)box;",
            "}",
            "static intptr_t kk_box_bool(intptr_t value) {",
            "  if (value == KK_NULL_SENTINEL) return value;",
            "  KKBoxedValue* box = (KKBoxedValue*)malloc(sizeof(KKBoxedValue));",
            "  if (!box) return value;",
            "  box->tag = KK_BOX_TAG_BOOL;",
            "  box->value = value != 0 ? 1 : 0;",
            "  return (intptr_t)box;",
            "}",
            "static intptr_t kk_unbox_int(intptr_t obj) {",
            "  if (obj == KK_NULL_SENTINEL) return 0;",
            "  if (obj > -(intptr_t)0x100000000LL && obj < (intptr_t)0x100000000LL) return obj;",
            "  KKBoxedValue* box = (KKBoxedValue*)(void*)obj;",
            "  if (box && box->tag == KK_BOX_TAG_INT) return box->value;",
            "  return obj;",
            "}",
            "static intptr_t kk_unbox_bool(intptr_t obj) {",
            "  if (obj == KK_NULL_SENTINEL) return 0;",
            "  if (obj > -(intptr_t)0x100000000LL && obj < (intptr_t)0x100000000LL) return obj != 0 ? 1 : 0;",
            "  KKBoxedValue* box = (KKBoxedValue*)(void*)obj;",
            "  if (box && box->tag == KK_BOX_TAG_BOOL) return box->value;",
            "  return obj != 0 ? 1 : 0;",
            "}",
            "static intptr_t kk_box_long(intptr_t value) {",
            "  if (value == KK_NULL_SENTINEL) return value;",
            "  KKBoxedValue* box = (KKBoxedValue*)malloc(sizeof(KKBoxedValue));",
            "  if (!box) return value;",
            "  box->tag = KK_BOX_TAG_LONG;",
            "  box->value = value;",
            "  return (intptr_t)box;",
            "}",
            "static intptr_t kk_unbox_long(intptr_t obj) {",
            "  if (obj == KK_NULL_SENTINEL) return 0;",
            "  KKBoxedValue* box = (KKBoxedValue*)(void*)obj;",
            "  if (box && box->tag == KK_BOX_TAG_LONG) return box->value;",
            "  return obj;",
            "}",
            "static intptr_t kk_float_to_bits(float f) {",
            "  uint32_t bits; memcpy(&bits, &f, sizeof(float)); return (intptr_t)bits;",
            "}",
            "static float kk_bits_to_float(intptr_t v) {",
            "  uint32_t bits = (uint32_t)v; float f; memcpy(&f, &bits, sizeof(float)); return f;",
            "}",
            "static intptr_t kk_double_to_bits(double d) {",
            "  intptr_t bits; memcpy(&bits, &d, sizeof(double)); return bits;",
            "}",
            "static double kk_bits_to_double(intptr_t v) {",
            "  double d; memcpy(&d, &v, sizeof(double)); return d;",
            "}",
            "static intptr_t kk_box_float(intptr_t value) {",
            "  if (value == KK_NULL_SENTINEL) return value;",
            "  KKBoxedValue* box = (KKBoxedValue*)malloc(sizeof(KKBoxedValue));",
            "  if (!box) return value;",
            "  box->tag = KK_BOX_TAG_FLOAT;",
            "  box->value = value;",
            "  return (intptr_t)box;",
            "}",
            "static intptr_t kk_unbox_float(intptr_t obj) {",
            "  if (obj == KK_NULL_SENTINEL) return 0;",
            "  KKBoxedValue* box = (KKBoxedValue*)(void*)obj;",
            "  if (box && box->tag == KK_BOX_TAG_FLOAT) return box->value;",
            "  return obj;",
            "}",
            "static intptr_t kk_box_double(intptr_t value) {",
            "  if (value == KK_NULL_SENTINEL) return value;",
            "  KKBoxedValue* box = (KKBoxedValue*)malloc(sizeof(KKBoxedValue));",
            "  if (!box) return value;",
            "  box->tag = KK_BOX_TAG_DOUBLE;",
            "  box->value = value;",
            "  return (intptr_t)box;",
            "}",
            "static intptr_t kk_unbox_double(intptr_t obj) {",
            "  if (obj == KK_NULL_SENTINEL) return 0;",
            "  KKBoxedValue* box = (KKBoxedValue*)(void*)obj;",
            "  if (box && box->tag == KK_BOX_TAG_DOUBLE) return box->value;",
            "  return obj;",
            "}",
            "static intptr_t kk_box_char(intptr_t value) {",
            "  if (value == KK_NULL_SENTINEL) return value;",
            "  KKBoxedValue* box = (KKBoxedValue*)malloc(sizeof(KKBoxedValue));",
            "  if (!box) return value;",
            "  box->tag = KK_BOX_TAG_CHAR;",
            "  box->value = value;",
            "  return (intptr_t)box;",
            "}",
            "static intptr_t kk_unbox_char(intptr_t obj) {",
            "  if (obj == KK_NULL_SENTINEL) return 0;",
            "  KKBoxedValue* box = (KKBoxedValue*)(void*)obj;",
            "  if (box && box->tag == KK_BOX_TAG_CHAR) return box->value;",
            "  return obj;",
            "}",
            "static void kk_println_float(intptr_t v) {",
            "  float f = kk_bits_to_float(v);",
            "  if (f >= -2e9f && f <= 2e9f && f == (float)(int)f) { printf(\"%.1f\\n\", (double)f); }",
            "  else { printf(\"%g\\n\", (double)f); }",
            "}",
            "static void kk_println_double(intptr_t v) {",
            "  double d = kk_bits_to_double(v);",
            "  if (d == (double)(long long)d && d >= -1e15 && d <= 1e15) { printf(\"%.1f\\n\", d); }",
            "  else { printf(\"%g\\n\", d); }",
            "}",
            "static void kk_println_char(intptr_t v) {",
            "  uint32_t cp = (uint32_t)v;",
            "  if (cp < 0x80) { putchar((int)cp); }",
            "  else if (cp < 0x800) { putchar((int)(0xC0 | (cp >> 6))); putchar((int)(0x80 | (cp & 0x3F))); }",
            "  else if (cp < 0x10000) { putchar((int)(0xE0 | (cp >> 12))); putchar((int)(0x80 | ((cp >> 6) & 0x3F))); putchar((int)(0x80 | (cp & 0x3F))); }",
            "  else { putchar((int)(0xF0 | (cp >> 18))); putchar((int)(0x80 | ((cp >> 12) & 0x3F))); putchar((int)(0x80 | ((cp >> 6) & 0x3F))); putchar((int)(0x80 | (cp & 0x3F))); }",
            "  putchar('\\n');",
            "}",
            "static void kk_println_any(void* obj) {",
            "  if ((intptr_t)obj == KK_NULL_SENTINEL) { puts(\"null\"); return; }",
            "  if ((intptr_t)obj > -(intptr_t)0x100000000LL && (intptr_t)obj < (intptr_t)0x100000000LL) {",
            "    printf(\"%ld\\n\", (long)(intptr_t)obj);",
            "    return;",
            "  }",
            "  KKBoxedValue* maybeBox = (KKBoxedValue*)(void*)obj;",
            "  if (maybeBox && maybeBox->tag == KK_BOX_TAG_BOOL) {",
            "    puts(maybeBox->value ? \"true\" : \"false\");",
            "    return;",
            "  }",
            "  if (maybeBox && maybeBox->tag == KK_BOX_TAG_INT) {",
            "    printf(\"%ld\\n\", (long)maybeBox->value);",
            "    return;",
            "  }",
            "  if (maybeBox && maybeBox->tag == KK_BOX_TAG_LONG) {",
            "    printf(\"%ld\\n\", (long)maybeBox->value);",
            "    return;",
            "  }",
            "  if (maybeBox && maybeBox->tag == KK_BOX_TAG_FLOAT) {",
            "    kk_println_float(maybeBox->value);",
            "    return;",
            "  }",
            "  if (maybeBox && maybeBox->tag == KK_BOX_TAG_DOUBLE) {",
            "    kk_println_double(maybeBox->value);",
            "    return;",
            "  }",
            "  if (maybeBox && maybeBox->tag == KK_BOX_TAG_CHAR) {",
            "    kk_println_char(maybeBox->value);",
            "    return;",
            "  }",
            "  KKString* s = (KKString*)obj;",
            "  if (!s) { puts(\"null\"); return; }",
            "  if (s->len < 0 || s->len > (1 << 20)) {",
            "    printf(\"%ld\\n\", (long)(intptr_t)obj);",
            "    return;",
            "  }",
            "  if (s->len > 0 && !s->bytes) {",
            "    printf(\"%ld\\n\", (long)(intptr_t)obj);",
            "    return;",
            "  }",
            "  if (s->bytes && s->len > 0) fwrite(s->bytes, 1, (size_t)s->len, stdout);",
            "  fputc('\\n', stdout);",
            "}",
            "typedef struct {",
            "  intptr_t functionId;",
            "  intptr_t label;",
            "  intptr_t completion;",
            "  intptr_t* spills;",
            "  intptr_t spillCount;",
            "} KKContinuationState;",
            "static intptr_t kk_coroutine_suspended(void) {",
            "  static int32_t token = 0;",
            "  return (intptr_t)(void*)&token;",
            "}",
            "static intptr_t kk_coroutine_continuation_new(intptr_t functionId) {",
            "  KKContinuationState* state = (KKContinuationState*)malloc(sizeof(KKContinuationState));",
            "  if (!state) return 0;",
            "  state->functionId = functionId;",
            "  state->label = 0;",
            "  state->completion = 0;",
            "  state->spills = NULL;",
            "  state->spillCount = 0;",
            "  return (intptr_t)state;",
            "}",
            "static intptr_t kk_coroutine_state_enter(intptr_t continuation, intptr_t functionId) {",
            "  KKContinuationState* state = (KKContinuationState*)(void*)continuation;",
            "  if (!state) return 0;",
            "  if (state->functionId != functionId) {",
            "    state->functionId = functionId;",
            "    state->label = 0;",
            "  }",
            "  return state->label;",
            "}",
            "static intptr_t kk_coroutine_state_set_label(intptr_t continuation, intptr_t label) {",
            "  KKContinuationState* state = (KKContinuationState*)(void*)continuation;",
            "  if (!state) return label;",
            "  state->label = label;",
            "  return label;",
            "}",
            "static intptr_t kk_coroutine_state_set_spill(intptr_t continuation, intptr_t slot, intptr_t value) {",
            "  KKContinuationState* state = (KKContinuationState*)(void*)continuation;",
            "  if (!state || slot < 0) return value;",
            "  if (slot >= state->spillCount) {",
            "    intptr_t newCount = slot + 1;",
            "    intptr_t* resized = (intptr_t*)realloc(state->spills, (size_t)newCount * sizeof(intptr_t));",
            "    if (!resized) return value;",
            "    for (intptr_t i = state->spillCount; i < newCount; ++i) resized[i] = 0;",
            "    state->spills = resized;",
            "    state->spillCount = newCount;",
            "  }",
            "  state->spills[slot] = value;",
            "  return value;",
            "}",
            "static intptr_t kk_coroutine_state_get_spill(intptr_t continuation, intptr_t slot) {",
            "  KKContinuationState* state = (KKContinuationState*)(void*)continuation;",
            "  if (!state || slot < 0 || slot >= state->spillCount || !state->spills) return 0;",
            "  return state->spills[slot];",
            "}",
            "static intptr_t kk_coroutine_state_set_completion(intptr_t continuation, intptr_t value) {",
            "  KKContinuationState* state = (KKContinuationState*)(void*)continuation;",
            "  if (!state) return value;",
            "  state->completion = value;",
            "  return value;",
            "}",
            "static intptr_t kk_coroutine_state_get_completion(intptr_t continuation) {",
            "  KKContinuationState* state = (KKContinuationState*)(void*)continuation;",
            "  if (!state) return 0;",
            "  return state->completion;",
            "}",
            "static intptr_t kk_coroutine_state_exit(intptr_t continuation, intptr_t value) {",
            "  KKContinuationState* state = (KKContinuationState*)(void*)continuation;",
            "  if (state) {",
            "    if (state->spills) free(state->spills);",
            "    free(state);",
            "  }",
            "  return value;",
            "}",
            "typedef intptr_t (*KKSuspendEntryFn)(intptr_t continuation, intptr_t* outThrown);",
            "static intptr_t kk_kxmini_delay(intptr_t milliseconds, intptr_t continuation) {",
            "  (void)continuation;",
            "  if (milliseconds > 0) {",
            "    usleep((useconds_t)(milliseconds * 1000));",
            "  }",
            "  return kk_coroutine_suspended();",
            "}",
            "static intptr_t delay(intptr_t milliseconds, intptr_t* outThrown) {",
            "  if (outThrown) { *outThrown = 0; }",
            "  return kk_kxmini_delay(milliseconds, 0);",
            "}",
            "static intptr_t kk_kxmini_run_loop(KKSuspendEntryFn entry, intptr_t functionId) {",
            "  if (!entry) return 0;",
            "  intptr_t continuation = kk_coroutine_continuation_new(functionId);",
            "  intptr_t suspended = kk_coroutine_suspended();",
            "  while (1) {",
            "    intptr_t thrown = 0;",
            "    intptr_t result = entry(continuation, &thrown);",
            "    if (thrown != 0) {",
            "      kk_coroutine_state_exit(continuation, 0);",
            "      return 0;",
            "    }",
            "    if (result != suspended) {",
            "      return result;",
            "    }",
            "  }",
            "}",
            "static intptr_t kk_kxmini_run_blocking(intptr_t entryRaw, intptr_t functionId) {",
            "  KKSuspendEntryFn entry = (KKSuspendEntryFn)(void*)entryRaw;",
            "  return kk_kxmini_run_loop(entry, functionId);",
            "}",
            "static intptr_t kk_kxmini_launch(intptr_t entryRaw, intptr_t functionId) {",
            "  (void)kk_kxmini_run_blocking(entryRaw, functionId);",
            "  return 0;",
            "}",
            "static intptr_t kk_kxmini_async(intptr_t entryRaw, intptr_t functionId) {",
            "  return kk_kxmini_run_blocking(entryRaw, functionId);",
            "}",
            "static intptr_t kk_kxmini_async_await(intptr_t handle) {",
            "  return handle;",
            "}",
            ""
        ]

        for global in globals {
            lines.append("static intptr_t \(globalSlotSymbol(for: global.symbol)) = 0;")
        }
        if !globals.isEmpty {
            lines.append("static void kk_register_module_globals(void) __attribute__((constructor));")
            lines.append("static void kk_unregister_module_globals(void) __attribute__((destructor));")
            lines.append("static void kk_register_module_globals(void) {")
            for global in globals {
                let slotSymbol = globalSlotSymbol(for: global.symbol)
                lines.append("  kk_register_global_root((void**)&\(slotSymbol));")
            }
            lines.append("}")
            lines.append("static void kk_unregister_module_globals(void) {")
            for global in globals {
                let slotSymbol = globalSlotSymbol(for: global.symbol)
                lines.append("  kk_unregister_global_root((void**)&\(slotSymbol));")
            }
            lines.append("}")
        }
        if !globals.isEmpty {
            lines.append("")
        }

        for callee in externalCallees {
            lines.append("extern intptr_t \(callee)();")
        }
        if !externalCallees.isEmpty {
            lines.append("")
        }

        for function in functions {
            let framePlan = frameMapPlans[function.symbol] ?? .empty
            let frameMapSymbol = frameMapDescriptorSymbol(for: function)
            if framePlan.rootCount > 0 {
                let offsetsSymbol = frameMapOffsetsSymbol(for: function)
                let offsetsText = framePlan.rootOffsets.map(String.init).joined(separator: ", ")
                lines.append("static const int32_t \(offsetsSymbol)[] = { \(offsetsText) };")
                lines.append("static const KKFrameMapDescriptor \(frameMapSymbol) = { \(framePlan.rootCount)u, \(offsetsSymbol) };")
            } else {
                lines.append("static const KKFrameMapDescriptor \(frameMapSymbol) = { 0u, NULL };")
            }
        }
        lines.append("")

        for function in functions {
            lines.append(functionPrototype(function: function, interner: interner) + ";")
        }
        lines.append("")
        lines.append("static int32_t kk_module_function_count(void) { return \(module.functionCount); }")
        lines.append("")

        for function in functions {
            lines.append(functionPrototype(function: function, interner: interner) + " {")
            lines.append(contentsOf: emitFunctionBody(
                function: function,
                frameMapPlan: frameMapPlans[function.symbol] ?? .empty,
                interner: interner,
                arena: module.arena,
                functionSymbols: functionSymbols,
                globalValueSymbols: globalValueSymbols
            ))
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
        frameMapPlan: FrameMapPlan,
        interner: StringInterner,
        arena: KIRArena,
        functionSymbols: [SymbolID: String],
        globalValueSymbols: [SymbolID: String]
    ) -> [String] {
        var lines: [String] = []
        var declared: Set<Int32> = []
        var callIndex = 0
        let functionID = max(0, Int(function.symbol.rawValue))
        var parameterNameBySymbol: [SymbolID: String] = [:]
        for (index, parameter) in function.params.enumerated() {
            parameterNameBySymbol[parameter.symbol] = "p\(index)"
        }

        if frameMapPlan.rootCount > 0 {
            lines.append("  intptr_t kk_gc_roots[\(frameMapPlan.rootCount)];")
            lines.append("  memset(kk_gc_roots, 0, sizeof(kk_gc_roots));")
            for (index, parameter) in function.params.enumerated() {
                guard let slot = frameMapPlan.parameterSlotBySymbol[parameter.symbol] else {
                    continue
                }
                lines.append("  kk_gc_roots[\(slot)] = p\(index);")
            }
        }
        lines.append("  kk_register_frame_map(\(functionID)u, &\(frameMapDescriptorSymbol(for: function)));")
        if frameMapPlan.rootCount > 0 {
            lines.append("  kk_push_frame(\(functionID)u, kk_gc_roots);")
        } else {
            lines.append("  kk_push_frame(\(functionID)u, NULL);")
        }
        lines.append("  if (outThrown) { *outThrown = 0; }")

        func syncRoot(_ id: KIRExprID) {
            guard let slot = frameMapPlan.exprSlotByID[id.rawValue] else {
                return
            }
            lines.append("  kk_gc_roots[\(slot)] = \(varName(id));")
        }

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
                    lines.append(
                        "  \(varName(result)) = \(valueExpr(value, interner: interner, functionSymbols: functionSymbols, globalValueSymbols: globalValueSymbols));"
                    )
                }
                syncRoot(result)

            case .select(let condition, let thenValue, let elseValue, let result):
                ensureDeclared(condition, declared: &declared, lines: &lines)
                ensureDeclared(thenValue, declared: &declared, lines: &lines)
                ensureDeclared(elseValue, declared: &declared, lines: &lines)
                ensureDeclared(result, declared: &declared, lines: &lines)
                lines.append("  \(varName(result)) = (\(varName(condition)) ? \(varName(thenValue)) : \(varName(elseValue)));")
                syncRoot(result)

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
                case .modulo:
                    opText = "%"
                case .equal:
                    opText = "=="
                case .notEqual:
                    opText = "!="
                case .lessThan:
                    opText = "<"
                case .lessOrEqual:
                    opText = "<="
                case .greaterThan:
                    opText = ">"
                case .greaterOrEqual:
                    opText = ">="
                case .logicalAnd:
                    opText = "&&"
                case .logicalOr:
                    opText = "||"
                }
                lines.append("  \(varName(result)) = (\(varName(lhs)) \(opText) \(varName(rhs)));")
                syncRoot(result)

            case .unary(let op, let operand, let result):
                ensureDeclared(result, declared: &declared, lines: &lines)
                ensureDeclared(operand, declared: &declared, lines: &lines)
                let unaryOpText: String
                switch op {
                case .not:
                    unaryOpText = "!"
                case .unaryPlus:
                    unaryOpText = "+"
                case .unaryMinus:
                    unaryOpText = "-"
                }
                lines.append("  \(varName(result)) = (\(unaryOpText)\(varName(operand)));")
                syncRoot(result)

            case .nullAssert(let operand, let result):
                ensureDeclared(result, declared: &declared, lines: &lines)
                ensureDeclared(operand, declared: &declared, lines: &lines)
                lines.append("  \(varName(result)) = \(varName(operand));")
                syncRoot(result)

            case .call(let symbol, let callee, let arguments, let result, let usesThrownChannel, let thrownResult):
                let calleeName = interner.resolve(callee)
                let argVars = arguments.map { arg -> String in
                    ensureDeclared(arg, declared: &declared, lines: &lines)
                    return varName(arg)
                }

                if let result {
                    ensureDeclared(result, declared: &declared, lines: &lines)
                }
                if let thrownResult {
                    ensureDeclared(thrownResult, declared: &declared, lines: &lines)
                }

                if calleeName == "println" || calleeName == "kk_println_any" {
                    let value = argVars.first ?? "0"
                    lines.append("  kk_println_any((void*)\(value));")
                    if let result {
                        lines.append("  \(varName(result)) = 0;")
                        syncRoot(result)
                    }
                    continue
                }

                if calleeName == "kk_println_float" || calleeName == "kk_println_double" || calleeName == "kk_println_char" {
                    let value = argVars.first ?? "0"
                    lines.append("  \(calleeName)(\(value));")
                    if let result {
                        lines.append("  \(varName(result)) = 0;")
                        syncRoot(result)
                    }
                    continue
                }

                if let cOp = LLVMBackend.builtinOps[calleeName] {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let expr = "(\(lhs) \(cOp) \(rhs))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if LLVMBackend.floatBuiltinOps.contains(calleeName) {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let cOp = Self.fpOpSymbol(calleeName)
                    let isComparison = calleeName.hasSuffix("eq") || calleeName.hasSuffix("ne") || calleeName.hasSuffix("lt") || calleeName.hasSuffix("le") || calleeName.hasSuffix("gt") || calleeName.hasSuffix("ge")
                    let expr: String
                    if calleeName == "kk_op_fmod" {
                        expr = "kk_float_to_bits(fmodf(kk_bits_to_float(\(lhs)), kk_bits_to_float(\(rhs))))"
                    } else if isComparison {
                        expr = "(intptr_t)(kk_bits_to_float(\(lhs)) \(cOp) kk_bits_to_float(\(rhs)))"
                    } else {
                        expr = "kk_float_to_bits(kk_bits_to_float(\(lhs)) \(cOp) kk_bits_to_float(\(rhs)))"
                    }
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if LLVMBackend.doubleBuiltinOps.contains(calleeName) {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let cOp = Self.fpOpSymbol(calleeName)
                    let isComparison = calleeName.hasSuffix("eq") || calleeName.hasSuffix("ne") || calleeName.hasSuffix("lt") || calleeName.hasSuffix("le") || calleeName.hasSuffix("gt") || calleeName.hasSuffix("ge")
                    let expr: String
                    if calleeName == "kk_op_dmod" {
                        expr = "kk_double_to_bits(fmod(kk_bits_to_double(\(lhs)), kk_bits_to_double(\(rhs))))"
                    } else if isComparison {
                        expr = "(intptr_t)(kk_bits_to_double(\(lhs)) \(cOp) kk_bits_to_double(\(rhs)))"
                    } else {
                        expr = "kk_double_to_bits(kk_bits_to_double(\(lhs)) \(cOp) kk_bits_to_double(\(rhs)))"
                    }
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
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
                        syncRoot(result)
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
                        syncRoot(result)
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
                    syncRoot(result)
                } else {
                    lines.append("  (void)\(callExpr);")
                }
                if calleeName == "kk_coroutine_continuation_new", let result {
                    lines.append("  kk_register_coroutine_root((void*)(uintptr_t)\(varName(result)));")
                }
                if calleeName == "kk_coroutine_state_exit", let continuation = argVars.first {
                    lines.append("  kk_unregister_coroutine_root((void*)(uintptr_t)\(continuation));")
                }
                if let thrownSlotName {
                    if let thrownResult {
                        lines.append("  \(varName(thrownResult)) = \(thrownSlotName);")
                    } else {
                        lines.append("  if (\(thrownSlotName) != 0) {")
                        lines.append("    if (outThrown) { *outThrown = \(thrownSlotName); }")
                        lines.append("    kk_pop_frame();")
                        lines.append("    return 0;")
                        lines.append("  }")
                    }
                }

            case .jumpIfNotNull(let value, let target):
                ensureDeclared(value, declared: &declared, lines: &lines)
                lines.append("  if (\(varName(value)) != 0) goto \(labelName(target));")

            case .copy(let from, let to):
                ensureDeclared(from, declared: &declared, lines: &lines)
                ensureDeclared(to, declared: &declared, lines: &lines)
                lines.append("  \(varName(to)) = \(varName(from));")

            case .rethrow(let value):
                ensureDeclared(value, declared: &declared, lines: &lines)
                lines.append("  if (outThrown) { *outThrown = \(varName(value)); }")
                lines.append("  kk_pop_frame();")
                lines.append("  return 0;")

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

    private func frameMapOffsetsSymbol(for function: KIRFunction) -> String {
        "kk_frame_map_offsets_\(max(0, Int(function.symbol.rawValue)))"
    }

    private func buildFrameMapPlan(function: KIRFunction) -> FrameMapPlan {
        var parameterSlotBySymbol: [SymbolID: Int] = [:]
        var nextSlot = 0
        for parameter in function.params {
            parameterSlotBySymbol[parameter.symbol] = nextSlot
            nextSlot += 1
        }

        let exprIDs = collectFrameRootExprIDs(function: function)
        var exprSlotByID: [Int32: Int] = [:]
        for exprID in exprIDs {
            exprSlotByID[exprID.rawValue] = nextSlot
            nextSlot += 1
        }

        let pointerStride = max(1, MemoryLayout<Int>.size)
        let rootOffsets = (0..<nextSlot).map { slot in
            Int32(slot * pointerStride)
        }

        return FrameMapPlan(
            parameterSlotBySymbol: parameterSlotBySymbol,
            exprSlotByID: exprSlotByID,
            rootOffsets: rootOffsets
        )
    }

    private func collectFrameRootExprIDs(function: KIRFunction) -> [KIRExprID] {
        var ids: Set<KIRExprID> = []

        for instruction in function.body {
            switch instruction {
            case .jumpIfEqual(let lhs, let rhs, _):
                ids.insert(lhs)
                ids.insert(rhs)
            case .constValue(let result, _):
                ids.insert(result)
            case .select(let condition, let thenValue, let elseValue, let result):
                ids.insert(condition)
                ids.insert(thenValue)
                ids.insert(elseValue)
                ids.insert(result)
            case .binary(_, let lhs, let rhs, let result):
                ids.insert(lhs)
                ids.insert(rhs)
                ids.insert(result)
            case .call(_, _, let arguments, let result, _, let thrownResult):
                for arg in arguments {
                    ids.insert(arg)
                }
                if let result {
                    ids.insert(result)
                }
                if let thrownResult {
                    ids.insert(thrownResult)
                }
            case .jumpIfNotNull(let value, _):
                ids.insert(value)
            case .copy(let from, let to):
                ids.insert(from)
                ids.insert(to)
            case .rethrow(let value):
                ids.insert(value)
            case .returnIfEqual(let lhs, let rhs):
                ids.insert(lhs)
                ids.insert(rhs)
            case .returnValue(let value):
                ids.insert(value)
            default:
                continue
            }
        }

        return ids.sorted(by: { $0.rawValue < $1.rawValue })
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

    private func valueExpr(
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

    private func globalSlotSymbol(for symbol: SymbolID) -> String {
        "kk_global_root_slot_\(max(0, Int(symbol.rawValue)))"
    }

    private static func fpOpSymbol(_ calleeName: String) -> String {
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

    private func formatCFloat(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", value)
        }
        return "\(value)"
    }

    private func formatCDouble(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", value)
        }
        return "\(value)"
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
            "kk_array_new",
            "kk_array_get",
            "kk_array_set",
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
            "delay"
        ]

        for decl in module.arena.declarations {
            guard case .function(let function) = decl else {
                continue
            }
            for instruction in function.body {
                guard case .call(let symbol, let callee, _, _, _, _) = instruction else {
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
                if LLVMBackend.floatBuiltinOps.contains(calleeName) || LLVMBackend.doubleBuiltinOps.contains(calleeName) {
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
