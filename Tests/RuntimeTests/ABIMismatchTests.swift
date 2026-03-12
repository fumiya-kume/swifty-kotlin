import CompilerCore
@testable import Runtime
import XCTest

final class ABIMismatchTests: XCTestCase {
    // MARK: - Helpers

    private func requireSpec(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> RuntimeABIFunctionSpec {
        let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == name })
        return try XCTUnwrap(spec, "'\(name)' not found in RuntimeABISpec.allFunctions", file: file, line: line)
    }

    // MARK: - Spec Integrity

    func testSpecVersionIsNonEmpty() {
        XCTAssertFalse(RuntimeABISpec.specVersion.isEmpty)
    }

    func testSpecVersionMatchesCompilerExterns() {
        XCTAssertEqual(
            RuntimeABISpec.specVersion,
            RuntimeABIExterns.specVersion,
            "Runtime spec version must match CompilerCore extern spec version"
        )
    }

    func testAllFunctionNamesAreUnique() {
        let names = RuntimeABISpec.allFunctions.map(\.name)
        let uniqueNames = Set(names)
        XCTAssertEqual(
            names.count,
            uniqueNames.count,
            "Duplicate function names found in RuntimeABISpec"
        )
    }

    func testAllFunctionNamesFollowKKPrefix() {
        for spec in RuntimeABISpec.allFunctions {
            XCTAssertTrue(
                spec.name.hasPrefix("kk_"),
                "Function '\(spec.name)' does not follow kk_ naming convention"
            )
        }
    }

    func testAllParameterNamesAreNonEmpty() {
        for spec in RuntimeABISpec.allFunctions {
            for param in spec.parameters {
                XCTAssertFalse(
                    param.name.isEmpty,
                    "Parameter in '\(spec.name)' has an empty name"
                )
            }
        }
    }

    func testParameterNamesUniquePerFunction() {
        for spec in RuntimeABISpec.allFunctions {
            let names = spec.parameters.map(\.name)
            let uniqueNames = Set(names)
            XCTAssertEqual(
                names.count,
                uniqueNames.count,
                "Duplicate parameter names in '\(spec.name)'"
            )
        }
    }

    // MARK: - Category Counts

    func testMemoryFunctionCount() {
        // kk_alloc, kk_gc_collect, kk_write_barrier
        XCTAssertEqual(RuntimeABISpec.memoryFunctions.count, 3)
    }

    func testExceptionFunctionCount() {
        // kk_throwable_new, kk_throwable_is_cancellation, kk_panic, kk_abort_unreachable,
        // kk_require, kk_check, kk_require_lazy, kk_check_lazy,
        // kk_error, kk_todo, kk_todo_noarg, kk_dispatch_error
        XCTAssertEqual(RuntimeABISpec.exceptionFunctions.count, 15)
    }

    func testStringFunctionCount() {
        // Keep this in sync with RuntimeABISpec.stringFunctions entries.
        XCTAssertEqual(RuntimeABISpec.stringFunctions.count, 90)
    }

    func testRegexFunctionCount() {
        // kk_regex_create, kk_string_matches_regex, kk_string_contains_regex,
        // kk_regex_find, kk_regex_findAll, kk_string_replace_regex,
        // kk_string_split_regex, kk_string_toRegex, kk_regex_pattern,
        // kk_match_result_value, kk_match_result_groupValues
        XCTAssertEqual(RuntimeABISpec.regexFunctions.count, 11)
    }

    func testPrintlnFunctionCount() {
        // kk_print_any, kk_println_any, kk_println_bool, kk_println_newline
        XCTAssertEqual(RuntimeABISpec.printlnFunctions.count, 4)
    }

    func testIOFunctionCount() {
        // kk_readline, kk_readln
        XCTAssertEqual(RuntimeABISpec.ioFunctions.count, 2)
    }

    func testGCFunctionCount() {
        // kk_register_global_root, kk_unregister_global_root,
        // kk_register_frame_map, kk_push_frame, kk_pop_frame,
        // kk_register_coroutine_root, kk_unregister_coroutine_root,
        // kk_runtime_heap_object_count, kk_runtime_force_reset
        XCTAssertEqual(RuntimeABISpec.gcFunctions.count, 9)
    }

    func testCoroutineFunctionCount() {
        // Keep this in sync with RuntimeABISpec.coroutineFunctions entries.
        // Includes CORO-002 cancellation and CORO-003 flow ownership helpers.
        XCTAssertEqual(RuntimeABISpec.coroutineFunctions.count, 44)
    }

    func testBoxingFunctionCount() {
        // Primitive boxing/unboxing helpers plus the lateinit initialization helpers.
        XCTAssertEqual(RuntimeABISpec.boxingFunctions.count, 14)
    }

    func testArrayFunctionCount() {
        // kk_array_new, kk_object_new, kk_object_type_id, kk_array_get, kk_array_get_inbounds,
        // kk_array_set, kk_vararg_spread_concat
        XCTAssertEqual(RuntimeABISpec.arrayFunctions.count, 7)
    }

    func testBitwiseFunctionCount() {
        // kk_bitwise_and, kk_bitwise_or, kk_bitwise_xor, kk_op_inv,
        // kk_op_shl, kk_op_shr, kk_op_ushr, kk_int_toString_radix
        XCTAssertEqual(RuntimeABISpec.bitwiseFunctions.count, 8)
    }

    func testPrimitiveNumericConversionFunctionCount() {
        // 13 conversion functions + 3 coercion functions = 16 (STDLIB-151: kk_long_to_int)
        XCTAssertEqual(RuntimeABISpec.primitiveNumericConversionFunctions.count, 16)
    }

    func testMathFunctionCount() {
        // kk_math_abs_int, kk_math_abs, kk_math_sqrt, kk_math_pow,
        // kk_math_ceil, kk_math_floor, kk_math_round
        XCTAssertEqual(RuntimeABISpec.mathFunctions.count, 7)
        XCTAssertEqual(RuntimeABISpec.randomFunctions.count, 5)
    }

    func testTotalFunctionCount() {
        let sections = [
            RuntimeABISpec.memoryFunctions,
            RuntimeABISpec.exceptionFunctions,
            RuntimeABISpec.stringFunctions,
            RuntimeABISpec.printlnFunctions,
            RuntimeABISpec.ioFunctions,
            RuntimeABISpec.systemFunctions,
            RuntimeABISpec.gcFunctions,
            RuntimeABISpec.coroutineFunctions,
            RuntimeABISpec.boxingFunctions,
            RuntimeABISpec.arrayFunctions,
            RuntimeABISpec.operatorFunctions,
            RuntimeABISpec.rangeFunctions,
            RuntimeABISpec.primitiveNumericConversionFunctions,
            RuntimeABISpec.kPropertyStubFunctions,
            RuntimeABISpec.delegateFunctions,
            RuntimeABISpec.bitwiseFunctions,
            RuntimeABISpec.mathFunctions,
            RuntimeABISpec.randomFunctions,
            RuntimeABISpec.collectionFunctions,
            RuntimeABISpec.sequenceFunctions,
            RuntimeABISpec.regexFunctions,
            RuntimeABISpec.comparatorFunctions,
        ]
        let expected = sections.reduce(0) { partial, section in
            partial + section.count
        }
        XCTAssertEqual(RuntimeABISpec.allFunctions.count, expected)
    }

    // MARK: - J16.1 Signature Verification (spec-fixed)

    func testKKAllocSignature() throws {
        let spec = try requireSpec("kk_alloc")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "size")
        XCTAssertEqual(spec.parameters[0].type, .uint32)
        XCTAssertEqual(spec.parameters[1].name, "typeInfo")
        XCTAssertEqual(spec.parameters[1].type, .constTypeInfoPointer,
                       "kk_alloc typeInfo must be const KTypeInfo * per J16.1")
    }

    func testKKGcCollectSignature() throws {
        let spec = try requireSpec("kk_gc_collect")
        XCTAssertEqual(spec.returnType, .void)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKWriteBarrierSignature() throws {
        let spec = try requireSpec("kk_write_barrier")
        XCTAssertEqual(spec.returnType, .void)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .opaquePointer)
        XCTAssertEqual(spec.parameters[1].type, .fieldAddrPointer)
    }

    func testKKThrowableNewSignature() throws {
        let spec = try requireSpec("kk_throwable_new")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .nullableOpaquePointer)
    }

    func testKKThrowableIsCancellationSignature() throws {
        let spec = try requireSpec("kk_throwable_is_cancellation")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKPanicSignature() throws {
        let spec = try requireSpec("kk_panic")
        XCTAssertEqual(spec.returnType, .noreturn)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .constCCharPointer)
    }

    func testKKStringFromUTF8Signature() throws {
        let spec = try requireSpec("kk_string_from_utf8")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .constUInt8Pointer)
        XCTAssertEqual(spec.parameters[1].type, .int32)
    }

    func testKKStringConcatSignature() throws {
        let spec = try requireSpec("kk_string_concat")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .nullableOpaquePointer)
        XCTAssertEqual(spec.parameters[1].type, .nullableOpaquePointer)
    }

    func testKKPrintlnAnySignature() throws {
        let spec = try requireSpec("kk_println_any")
        XCTAssertEqual(spec.returnType, .void)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .nullableOpaquePointer)
    }

    func testKKStringLengthSignature() throws {
        let spec = try requireSpec("kk_string_length")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKOpIsSignature() throws {
        let spec = try requireSpec("kk_op_is")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
    }

    func testKKCoroutineSuspendedSignature() throws {
        let spec = try requireSpec("kk_coroutine_suspended")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    // MARK: - C Declaration Generation

    func testCDeclarationForKKAlloc() throws {
        let spec = try requireSpec("kk_alloc")
        XCTAssertEqual(
            spec.cDeclaration,
            "void * kk_alloc(uint32_t size, const KTypeInfo * typeInfo);"
        )
    }

    func testCDeclarationForKKGcCollect() throws {
        let spec = try requireSpec("kk_gc_collect")
        XCTAssertEqual(spec.cDeclaration, "void kk_gc_collect(void);")
    }

    func testCDeclarationForKKPrintlnAny() throws {
        let spec = try requireSpec("kk_println_any")
        XCTAssertEqual(
            spec.cDeclaration,
            "void kk_println_any(void * _Nullable obj);"
        )
    }

    func testCDeclarationForKKPanic() throws {
        let spec = try requireSpec("kk_panic")
        XCTAssertEqual(
            spec.cDeclaration,
            "_Noreturn void kk_panic(const char * cstr);"
        )
    }

    func testCDeclarationForKKAbortUnreachable() throws {
        let spec = try requireSpec("kk_abort_unreachable")
        XCTAssertEqual(
            spec.cDeclaration,
            "intptr_t kk_abort_unreachable(intptr_t * _Nullable outThrown);"
        )
    }

    // MARK: - Header Generation

    func testGeneratedHeaderContainsGuard() {
        let header = RuntimeABISpec.generateCHeader()
        XCTAssertTrue(header.contains("#ifndef KK_RUNTIME_ABI_H"))
        XCTAssertTrue(header.contains("#define KK_RUNTIME_ABI_H"))
        XCTAssertTrue(header.contains("#endif"))
    }

    func testGeneratedHeaderContainsAllFunctions() {
        let header = RuntimeABISpec.generateCHeader()
        let headerLines = Set(
            header
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        )
        for spec in RuntimeABISpec.allFunctions {
            XCTAssertTrue(
                headerLines.contains(spec.cDeclaration),
                "Generated header missing declaration for '\(spec.name)': expected line '\(spec.cDeclaration)'"
            )
        }
    }

    func testGeneratedHeaderContainsSpecVersion() {
        let header = RuntimeABISpec.generateCHeader()
        XCTAssertTrue(header.contains(RuntimeABISpec.specVersion))
    }

    func testGeneratedHeaderContainsSectionMarkers() {
        let header = RuntimeABISpec.generateCHeader()
        XCTAssertTrue(header.contains("Memory"))
        XCTAssertTrue(header.contains("Exception"))
        XCTAssertTrue(header.contains("String"))
        XCTAssertTrue(header.contains("Println"))
        XCTAssertTrue(header.contains("GC"))
        XCTAssertTrue(header.contains("Coroutine"))
        XCTAssertTrue(header.contains("Boxing"))
        XCTAssertTrue(header.contains("Array"))
        XCTAssertTrue(header.contains("TypeCheck"))
        XCTAssertTrue(header.contains("Bitwise"))
    }
}
