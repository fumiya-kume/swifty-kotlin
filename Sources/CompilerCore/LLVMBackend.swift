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
        "kk_op_add": "+", "kk_op_sub": "-", "kk_op_mul": "*", "kk_op_div": "/", "kk_op_eq": "=="
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
            "static void kk_println_any(intptr_t obj) {",
            "  if (obj == KK_NULL_SENTINEL) { puts(\"null\"); return; }",
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
            "",
            "/* ── Structured Concurrency (CoroutineScope / Job) ── */",
            "typedef struct KKCoroutineScope {",
            "  intptr_t* children;",
            "  intptr_t childCount;",
            "  intptr_t childCapacity;",
            "  int cancelled;",
            "} KKCoroutineScope;",
            "typedef struct KKJob {",
            "  int completed;",
            "  int cancelled;",
            "  intptr_t result;",
            "  intptr_t scopeHandle;",
            "} KKJob;",
            "static intptr_t kk_coroutine_scope_new(void) {",
            "  KKCoroutineScope* scope = (KKCoroutineScope*)calloc(1, sizeof(KKCoroutineScope));",
            "  scope->childCapacity = 4;",
            "  scope->children = (intptr_t*)calloc(4, sizeof(intptr_t));",
            "  return (intptr_t)(void*)scope;",
            "}",
            "static intptr_t kk_coroutine_scope_cancel(intptr_t scopeHandle) {",
            "  KKCoroutineScope* scope = (KKCoroutineScope*)(void*)scopeHandle;",
            "  if (!scope) return 0;",
            "  scope->cancelled = 1;",
            "  for (intptr_t i = 0; i < scope->childCount; i++) {",
            "    KKJob* job = (KKJob*)(void*)scope->children[i];",
            "    if (job) job->cancelled = 1;",
            "  }",
            "  return 0;",
            "}",
            "static intptr_t kk_coroutine_scope_is_cancelled(intptr_t scopeHandle) {",
            "  KKCoroutineScope* scope = (KKCoroutineScope*)(void*)scopeHandle;",
            "  if (!scope) return 0;",
            "  return scope->cancelled ? 1 : 0;",
            "}",
            "static intptr_t kk_coroutine_scope_join_all(intptr_t scopeHandle) {",
            "  (void)scopeHandle;",
            "  return 0;",
            "}",
            "static intptr_t kk_coroutine_scope_release(intptr_t scopeHandle) {",
            "  KKCoroutineScope* scope = (KKCoroutineScope*)(void*)scopeHandle;",
            "  if (scope) {",
            "    if (scope->children) free(scope->children);",
            "    free(scope);",
            "  }",
            "  return 0;",
            "}",
            "static intptr_t kk_job_new(intptr_t scopeHandle) {",
            "  KKJob* job = (KKJob*)calloc(1, sizeof(KKJob));",
            "  job->scopeHandle = scopeHandle;",
            "  KKCoroutineScope* scope = (KKCoroutineScope*)(void*)scopeHandle;",
            "  if (scope) {",
            "    if (scope->childCount >= scope->childCapacity) {",
            "      scope->childCapacity *= 2;",
            "      scope->children = (intptr_t*)realloc(scope->children, (size_t)scope->childCapacity * sizeof(intptr_t));",
            "    }",
            "    scope->children[scope->childCount++] = (intptr_t)(void*)job;",
            "  }",
            "  return (intptr_t)(void*)job;",
            "}",
            "static intptr_t kk_job_complete(intptr_t jobHandle, intptr_t value) {",
            "  KKJob* job = (KKJob*)(void*)jobHandle;",
            "  if (!job) return 0;",
            "  job->result = value;",
            "  job->completed = 1;",
            "  return 0;",
            "}",
            "static intptr_t kk_job_join(intptr_t jobHandle) {",
            "  KKJob* job = (KKJob*)(void*)jobHandle;",
            "  if (!job) return 0;",
            "  return job->result;",
            "}",
            "static intptr_t kk_job_cancel(intptr_t jobHandle) {",
            "  KKJob* job = (KKJob*)(void*)jobHandle;",
            "  if (!job) return 0;",
            "  job->cancelled = 1;",
            "  return 0;",
            "}",
            "static intptr_t kk_job_is_cancelled(intptr_t jobHandle) {",
            "  KKJob* job = (KKJob*)(void*)jobHandle;",
            "  if (!job) return 0;",
            "  if (job->cancelled) return 1;",
            "  KKCoroutineScope* scope = (KKCoroutineScope*)(void*)job->scopeHandle;",
            "  if (scope && scope->cancelled) return 1;",
            "  return 0;",
            "}",
            "static intptr_t kk_scoped_launch(intptr_t scopeHandle, intptr_t entryRaw, intptr_t functionId) {",
            "  intptr_t jobHandle = kk_job_new(scopeHandle);",
            "  intptr_t result = kk_kxmini_run_blocking(entryRaw, functionId);",
            "  kk_job_complete(jobHandle, result);",
            "  return jobHandle;",
            "}",
            "static intptr_t kk_scoped_async(intptr_t scopeHandle, intptr_t entryRaw, intptr_t functionId) {",
            "  intptr_t jobHandle = kk_job_new(scopeHandle);",
            "  intptr_t result = kk_kxmini_run_blocking(entryRaw, functionId);",
            "  kk_job_complete(jobHandle, result);",
            "  return jobHandle;",
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
                case .equal:
                    opText = "=="
                }
                lines.append("  \(varName(result)) = (\(varName(lhs)) \(opText) \(varName(rhs)));")
                syncRoot(result)

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
            case .call(_, _, let arguments, let result, _):
                for arg in arguments {
                    ids.insert(arg)
                }
                if let result {
                    ids.insert(result)
                }
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
            "delay",
            "kk_coroutine_scope_new",
            "kk_coroutine_scope_cancel",
            "kk_coroutine_scope_join_all",
            "kk_coroutine_scope_release",
            "kk_coroutine_scope_is_cancelled",
            "kk_job_new",
            "kk_job_join",
            "kk_job_complete",
            "kk_job_cancel",
            "kk_job_is_cancelled",
            "kk_scoped_launch",
            "kk_scoped_async"
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
