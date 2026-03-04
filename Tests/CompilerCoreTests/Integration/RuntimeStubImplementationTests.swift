@testable import CompilerCore
import Foundation
import XCTest

/// Tests verifying that the C runtime preamble contains proper GC data structure
/// definitions and function implementations (not no-op stubs), and that the
/// LLVM C API backend declares runtime functions as external (not internal no-ops).
final class RuntimeStubImplementationTests: XCTestCase {
    // MARK: - Helpers

    private func makePreamble() -> String {
        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        return backend.cRuntimePreamble().joined(separator: "\n")
    }

    private func makeSimpleModule(interner: StringInterner) -> KIRModule {
        let arena = KIRArena()
        let main = KIRFunction(
            symbol: SymbolID(rawValue: 100),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        let mainID = arena.appendDecl(.function(main))
        return KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )
    }

    // MARK: - C Preamble Data Structure Tests

    func testPreambleContainsFrameMapEntryType() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("typedef struct { uint32_t functionID; uint32_t rootCount; int32_t* rootOffsets; } KKFrameMapEntry;"),
            "Preamble must define KKFrameMapEntry struct"
        )
    }

    func testPreambleContainsActiveFrameType() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("typedef struct { uint32_t functionID; void* frameBase; } KKActiveFrame;"),
            "Preamble must define KKActiveFrame struct"
        )
    }

    func testPreambleContainsFrameMapStorage() {
        let preamble = makePreamble()
        XCTAssertTrue(preamble.contains("static KKFrameMapEntry* kk_rt_fmaps = NULL;"))
        XCTAssertTrue(preamble.contains("static uint32_t kk_rt_fmap_cnt = 0;"))
        XCTAssertTrue(preamble.contains("static uint32_t kk_rt_fmap_cap = 0;"))
    }

    func testPreambleContainsActiveFrameStorage() {
        let preamble = makePreamble()
        XCTAssertTrue(preamble.contains("static KKActiveFrame* kk_rt_frames = NULL;"))
        XCTAssertTrue(preamble.contains("static uint32_t kk_rt_frame_cnt = 0;"))
        XCTAssertTrue(preamble.contains("static uint32_t kk_rt_frame_cap = 0;"))
    }

    func testPreambleContainsGlobalRootStorage() {
        let preamble = makePreamble()
        XCTAssertTrue(preamble.contains("static void*** kk_rt_groots = NULL;"))
        XCTAssertTrue(preamble.contains("static uint32_t kk_rt_groot_cnt = 0;"))
        XCTAssertTrue(preamble.contains("static uint32_t kk_rt_groot_cap = 0;"))
    }

    func testPreambleContainsCoroutineRootStorage() {
        let preamble = makePreamble()
        XCTAssertTrue(preamble.contains("static void** kk_rt_croots = NULL;"))
        XCTAssertTrue(preamble.contains("static uint32_t kk_rt_croot_cnt = 0;"))
        XCTAssertTrue(preamble.contains("static uint32_t kk_rt_croot_cap = 0;"))
    }

    // MARK: - kk_register_frame_map Tests

    func testRegisterFrameMapIsNotNoOp() {
        let preamble = makePreamble()
        // Old no-op stub had: (void)functionID; (void)mapPtr;
        XCTAssertFalse(
            preamble.contains("(void)functionID;\n  (void)mapPtr;"),
            "kk_register_frame_map must not be a no-op stub"
        )
    }

    func testRegisterFrameMapHandlesNullMapPtr() {
        let preamble = makePreamble()
        // When mapPtr is NULL, it should unregister by searching for the functionID
        XCTAssertTrue(
            preamble.contains("if (!mapPtr)"),
            "kk_register_frame_map must handle NULL mapPtr for unregistration"
        )
    }

    func testRegisterFrameMapCopiesDescriptorOffsets() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("memcpy(offs, desc->rootOffsets, cnt * sizeof(int32_t))"),
            "kk_register_frame_map must deep-copy root offsets from descriptor"
        )
    }

    func testRegisterFrameMapHandlesMallocFailure() {
        let preamble = makePreamble()
        // When malloc fails, cnt must be reset to 0 to avoid storing corrupt entry
        XCTAssertTrue(
            preamble.contains("if (!offs) { cnt = 0; }"),
            "kk_register_frame_map must reset cnt to 0 on malloc failure"
        )
    }

    func testRegisterFrameMapHandlesNullRootOffsets() {
        let preamble = makePreamble()
        // When desc->rootOffsets is NULL but rootCount > 0, cnt must be reset to 0
        XCTAssertTrue(
            preamble.contains("} else { cnt = 0; }"),
            "kk_register_frame_map must reset cnt when rootOffsets is NULL"
        )
    }

    func testRegisterFrameMapDynamicallyGrowsStorage() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("realloc(kk_rt_fmaps, nc * sizeof(KKFrameMapEntry))"),
            "kk_register_frame_map must use realloc for dynamic growth"
        )
    }

    func testRegisterFrameMapUpdatesExistingEntry() {
        let preamble = makePreamble()
        // Must search for existing functionID and update in-place
        XCTAssertTrue(
            preamble.contains("kk_rt_fmaps[i].functionID == functionID"),
            "kk_register_frame_map must check for existing entries to update"
        )
    }

    // MARK: - kk_push_frame / kk_pop_frame Tests

    func testPushFrameIsNotNoOp() {
        let preamble = makePreamble()
        XCTAssertFalse(
            preamble.contains("(void)functionID;\n  (void)frameBase;"),
            "kk_push_frame must not be a no-op stub"
        )
    }

    func testPushFrameDynamicallyGrowsStorage() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("realloc(kk_rt_frames, nc * sizeof(KKActiveFrame))"),
            "kk_push_frame must use realloc for dynamic growth"
        )
    }

    func testPushFrameStoresFunctionIDAndFrameBase() {
        let preamble = makePreamble()
        XCTAssertTrue(preamble.contains("kk_rt_frames[kk_rt_frame_cnt].functionID = functionID;"))
        XCTAssertTrue(preamble.contains("kk_rt_frames[kk_rt_frame_cnt].frameBase = frameBase;"))
    }

    func testPopFrameDecrementsCount() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("if (kk_rt_frame_cnt > 0) kk_rt_frame_cnt--;"),
            "kk_pop_frame must safely decrement frame count"
        )
    }

    // MARK: - kk_register_global_root / kk_unregister_global_root Tests

    func testRegisterGlobalRootIsNotNoOp() {
        let preamble = makePreamble()
        XCTAssertFalse(
            preamble.contains("void kk_register_global_root(void** slot) {\n  (void)slot;\n}"),
            "kk_register_global_root must not be a no-op stub"
        )
    }

    func testRegisterGlobalRootChecksNullSlot() {
        let preamble = makePreamble()
        // The function at this position contains: if (!slot) return;
        let registerSection = preamble.components(separatedBy: "kk_register_global_root(void** slot)")
        XCTAssertTrue(registerSection.count > 1, "kk_register_global_root must exist")
        XCTAssertTrue(registerSection[1].contains("if (!slot) return;"))
    }

    func testRegisterGlobalRootDeduplicates() {
        let preamble = makePreamble()
        // Must check if slot already registered: if (kk_rt_groots[i] == slot) return;
        XCTAssertTrue(
            preamble.contains("if (kk_rt_groots[i] == slot) return;"),
            "kk_register_global_root must deduplicate"
        )
    }

    func testRegisterGlobalRootDynamicallyGrows() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("realloc(kk_rt_groots, nc * sizeof(void**))"),
            "kk_register_global_root must use realloc for dynamic growth"
        )
    }

    func testUnregisterGlobalRootSwapRemoves() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("kk_rt_groots[i] = kk_rt_groots[--kk_rt_groot_cnt];"),
            "kk_unregister_global_root must swap-remove"
        )
    }

    // MARK: - kk_register_coroutine_root / kk_unregister_coroutine_root Tests

    func testRegisterCoroutineRootIsNotNoOp() {
        let preamble = makePreamble()
        XCTAssertFalse(
            preamble.contains("void kk_register_coroutine_root(void* value) {\n  (void)value;\n}"),
            "kk_register_coroutine_root must not be a no-op stub"
        )
    }

    func testRegisterCoroutineRootChecksNullValue() {
        let preamble = makePreamble()
        let section = preamble.components(separatedBy: "kk_register_coroutine_root(void* value)")
        XCTAssertTrue(section.count > 1, "kk_register_coroutine_root must exist")
        XCTAssertTrue(section[1].contains("if (!value) return;"))
    }

    func testRegisterCoroutineRootDeduplicates() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("if (kk_rt_croots[i] == value) return;"),
            "kk_register_coroutine_root must deduplicate"
        )
    }

    func testRegisterCoroutineRootDynamicallyGrows() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("realloc(kk_rt_croots, nc * sizeof(void*))"),
            "kk_register_coroutine_root must use realloc for dynamic growth"
        )
    }

    func testUnregisterCoroutineRootSwapRemoves() {
        let preamble = makePreamble()
        XCTAssertTrue(
            preamble.contains("kk_rt_croots[i] = kk_rt_croots[--kk_rt_croot_cnt];"),
            "kk_unregister_coroutine_root must swap-remove"
        )
    }

    // MARK: - Synthetic C Backend Integration Tests

    func testSyntheticCBackendEmitsFrameMapRegistrationInFunctionBody() throws {
        let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
        guard FileManager.default.fileExists(atPath: clangPath) else {
            throw XCTSkip("clang is not available in this environment.")
        }
        let interner = StringInterner()
        let module = makeSimpleModule(interner: interner)

        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, runtime: runtime, outputIRPath: irPath, interner: interner)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        // The generated C code (compiled to LLVM IR) should reference runtime functions
        XCTAssertTrue(ir.contains("kk_register_frame_map"), "Synthetic backend must emit kk_register_frame_map calls")
        XCTAssertTrue(ir.contains("kk_push_frame"), "Synthetic backend must emit kk_push_frame calls")
        XCTAssertTrue(ir.contains("kk_pop_frame"), "Synthetic backend must emit kk_pop_frame calls")
    }

    func testSyntheticCBackendCompilesWithRuntimeStubs() throws {
        let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
        guard FileManager.default.fileExists(atPath: clangPath) else {
            throw XCTSkip("clang is not available in this environment.")
        }
        let interner = StringInterner()
        let module = makeSimpleModule(interner: interner)

        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let objPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o").path

        // This must not throw - the C preamble with runtime stubs must compile cleanly
        try backend.emitObject(module: module, runtime: runtime, outputObjectPath: objPath, interner: interner)
        XCTAssertTrue(FileManager.default.fileExists(atPath: objPath), "Object file must be generated successfully")
    }

    func testSyntheticCBackendEmitsFrameMapDescriptorSymbols() throws {
        let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
        guard FileManager.default.fileExists(atPath: clangPath) else {
            throw XCTSkip("clang is not available in this environment.")
        }
        let interner = StringInterner()
        let module = makeSimpleModule(interner: interner)

        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, runtime: runtime, outputIRPath: irPath, interner: interner)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        // Frame map descriptors should be emitted as globals
        XCTAssertTrue(ir.contains("kk_frame_map_offsets_") || ir.contains("KKFrameMapDescriptor"),
                      "Synthetic backend must emit frame map descriptor data")
    }

    // MARK: - LLVM C API Backend Tests

    func testLlvmCapiBackendDefinesFrameRuntimeFunctionsWithWeakLinkage() throws {
        guard let bindings = LLVMCAPIBindings.load(),
              bindings.smokeTestContextLifecycle()
        else {
            throw XCTSkip("LLVM C API bindings are unavailable in this environment.")
        }

        let interner = StringInterner()
        let module = makeSimpleModule(interner: interner)

        let backend = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine(),
            isStrictMode: true
        )
        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, runtime: runtime, outputIRPath: irPath, interner: interner)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        // Functions must be referenced in the IR
        XCTAssertTrue(ir.contains("@kk_register_frame_map"), "LLVM IR must reference kk_register_frame_map")
        XCTAssertTrue(ir.contains("@kk_push_frame"), "LLVM IR must reference kk_push_frame")
        XCTAssertTrue(ir.contains("@kk_pop_frame"), "LLVM IR must reference kk_pop_frame")

        // Must NOT contain internal linkage definitions for these functions
        let lines = ir.components(separatedBy: "\n")
        for line in lines {
            if line.contains("kk_register_frame_map") || line.contains("kk_push_frame") || line.contains("kk_pop_frame") {
                if line.contains("define") {
                    XCTAssertFalse(
                        line.contains("internal"),
                        "Runtime functions must not be defined as internal: \(line)"
                    )
                }
            }
        }
    }

    // MARK: - Preamble Weak Attribute Tests

    func testAllRuntimeFunctionsHaveWeakAttribute() {
        let preamble = makePreamble()
        let runtimeFunctions = [
            "kk_register_frame_map",
            "kk_push_frame",
            "kk_pop_frame",
            "kk_register_global_root",
            "kk_unregister_global_root",
            "kk_register_coroutine_root",
            "kk_unregister_coroutine_root"
        ]
        for name in runtimeFunctions {
            XCTAssertTrue(
                preamble.contains("__attribute__((weak)) void \(name)"),
                "Runtime function \(name) must have __attribute__((weak))"
            )
        }
    }
}
