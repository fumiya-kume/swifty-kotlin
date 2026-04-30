import RuntimeABI
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
            "Runtime spec version must match shared RuntimeABI extern spec version"
        )
    }

    func testAllFunctionNamesAreUnique() {
        let reflectionNames =
            RuntimeABISpec.kPropertyStubFunctions.map(\.name)
            + RuntimeABISpec.kFunctionFunctions.map(\.name)
            + RuntimeABISpec.callableRefFunctions.map(\.name)
        let uniqueNames = Set(reflectionNames)
        XCTAssertEqual(
            reflectionNames.count,
            uniqueNames.count,
            "Duplicate reflection function names found in RuntimeABISpec"
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
        // kk_throwable_new, kk_throwable_is_cancellation, kk_throwable_printStackTrace,
        // kk_throwable_* properties/helpers,
        // kk_no_when_branch_matched_exception_new* constructors,
        // kk_concurrent_modification_exception_new* constructors,
        // kk_array_index_out_of_bounds_exception_new* constructors,
        // kk_panic, kk_abort_unreachable,
        // kk_require, kk_check, kk_require_lazy, kk_check_lazy,
        // kk_precondition_assert, kk_precondition_assert_lazy,
        // kk_assertions_enabled, kk_assertions_set_enabled, kk_assertions_reset,
        // kk_reentrant_read_write_lock_read,
        // kk_error, kk_todo, kk_todo_noarg, kk_dispatch_error
        XCTAssertEqual(RuntimeABISpec.exceptionFunctions.count, 38)
    }

    func testTestFrameworkFunctionCount() {
        XCTAssertEqual(RuntimeABISpec.testFunctions.count, 6)
    }

    func testStringFunctionCount() {
        // Keep this in sync with RuntimeABISpec.stringFunctions entries.
        XCTAssertEqual(RuntimeABISpec.stringFunctions.count, 187)
    }

    func testRegexFunctionCount() {
        // kk_regex_create, kk_string_matches_regex, kk_string_contains_regex,
        // kk_regex_find, kk_regex_findAll, kk_string_replace_regex,
        // kk_string_split_regex, kk_string_toRegex, kk_regex_pattern,
        // kk_match_result_value, kk_match_result_groupValues,
        // kk_regex_replace_lambda, kk_regex_matchEntire,
        // kk_regex_create_with_option, kk_regex_create_with_options,
        // kk_regex_containsMatchIn,
        // kk_match_result_groups, kk_match_group_collection_get,
        // kk_match_group_value, kk_match_group_range,
        // kk_string_chunked, kk_string_chunkedSequence_transform,
        // kk_string_windowed, kk_string_windowedSequence_partial,
        // kk_string_windowedSequence_transform,
        // kk_string_commonPrefixWith, kk_string_commonSuffixWith,
        // kk_string_zipWithNext
        // STDLIB-REGEX-097: kk_regex_group_names
        // STDLIB-REGEX-094: kk_regex_matches, kk_regex_from_literal, kk_string_replaceFirst_regex
        XCTAssertEqual(RuntimeABISpec.regexFunctions.count, 38)
    }

    func testPrintAndPrintlnFunctionCount() {
        // Includes Int/Bool/ULong println overload helpers plus no-arg newline emission.
        XCTAssertEqual(RuntimeABISpec.consolePrintFunctions.count, 6)
    }

    func testIOFunctionCount() {
        // kk_readline, kk_readln, kk_readlnOrNull
        XCTAssertEqual(RuntimeABISpec.ioFunctions.count, 3)
    }

    func testGCFunctionCount() {
        // kk_register_global_root, kk_unregister_global_root,
        // kk_register_frame_map, kk_push_frame, kk_pop_frame,
        // kk_register_coroutine_root, kk_unregister_coroutine_root,
        // kk_runtime_heap_object_count, kk_runtime_force_reset
        XCTAssertEqual(RuntimeABISpec.gcFunctions.count, 9)
    }

    func testThreadLocalFunctionCount() {
        XCTAssertEqual(RuntimeABISpec.threadLocalFunctions.count, 2)
    }

    func testThreadFunctionCount() {
        XCTAssertEqual(RuntimeABISpec.threadFunctions.count, 1)
    }

    func testCoroutineFunctionCount() {
        // Keep this in sync with RuntimeABISpec.coroutineFunctions entries.
        // Includes the Job lifecycle helpers plus the read-write lock runtime entry points.
        XCTAssertEqual(RuntimeABISpec.coroutineFunctions.count, 121)
    }

    func testBoxingFunctionCount() {
        // Primitive boxing/unboxing helpers plus the lateinit initialization helpers.
        XCTAssertEqual(RuntimeABISpec.boxingFunctions.count, 14)
    }

    func testArrayFunctionCount() {
        // kk_array_new, kk_array_of_nulls, kk_object_new, kk_object_type_id, kk_array_get,
        // kk_array_get_inbounds, kk_array_set, kk_array_binarySearch_compare, kk_vararg_spread_concat
        XCTAssertEqual(RuntimeABISpec.arrayFunctions.count, 9)
    }

    func testBitwiseFunctionCount() {
        // Includes integer and long bitwise helpers plus bit-counting utilities.
        XCTAssertEqual(RuntimeABISpec.bitwiseFunctions.count, 36)
    }

    func testFloorDivABISignatures() throws {
        for name in ["kk_op_floor_div", "kk_op_lfloor_div"] {
            let spec = try requireSpec(name)
            XCTAssertEqual(spec.returnType, .intptr)
            XCTAssertEqual(spec.parameters.map(\.type), [.intptr, .intptr])
            XCTAssertEqual(spec.parameters.map(\.name), ["lhs", "rhs"])
        }
    }

    func testPrimitiveNumericConversionFunctionCount() {
        // Includes signed/unsigned/char conversions plus coercion helpers.
        XCTAssertEqual(RuntimeABISpec.primitiveNumericConversionFunctions.count, 75)
    }

    func testMathFunctionCount() {
        // Current math ABI surface:
        // - 23 Double/int/basic entries through PI/E
        // - 21 Float overloads
        // - 2 Double expm1/ln1p helpers
        // - 12 STDLIB-MATH-006 max/min overload helpers
        // - 11 STDLIB-MATH-007 remainder/nextTowards/withSign/pow helpers
        // - 4 roundToInt/roundToLong helpers
        // - 6 ulp/nextUp/nextDown helpers
        // - 2 integral sign property helpers
        // - 3 coercion helpers
        // - 16 IEEE 754 rounding mode convenience entry points (8 Double + 8 Float)
        // - 14 STDLIB-MATH-112 numeric constants (5 Double + 5 Float + 2 Int + 2 Long)
        // - 2 generic mode-dispatch (round_mode, round_mode_float)
        // - 8 STDLIB-MATH-109 hyperbolic/cbrt entries (sinh, cosh, tanh, cbrt + Float overloads)
        // - 6 STDLIB-MATH-113 floating-point helpers
        XCTAssertEqual(RuntimeABISpec.mathFunctions.count, 130)
        // Random ABI includes default, seeded, bounded numeric helpers, range overloads, UInt/ULong helpers, byte array/unsigned byte helpers, SecureRandom helpers, and explicit bit extraction.
        XCTAssertEqual(RuntimeABISpec.randomFunctions.count, 36)
    }

    func testTotalFunctionCount() {
        let sections = [
            RuntimeABISpec.memoryFunctions,
            RuntimeABISpec.exceptionFunctions,
            RuntimeABISpec.testFunctions,
            RuntimeABISpec.stringFunctions,
            RuntimeABISpec.stringBridgeFunctions,
            RuntimeABISpec.consolePrintFunctions,
            RuntimeABISpec.ioFunctions,
            RuntimeABISpec.systemFunctions,
            RuntimeABISpec.gcFunctions,
            RuntimeABISpec.coroutineFunctions,
            RuntimeABISpec.boxingFunctions,
            RuntimeABISpec.arrayFunctions,
            RuntimeABISpec.operatorFunctions,
            RuntimeABISpec.rangeFunctions,
            RuntimeABISpec.primitiveNumericConversionFunctions,
            RuntimeABISpec.numericRuntimeBridgeFunctions,
            RuntimeABISpec.kPropertyStubFunctions,
            RuntimeABISpec.kParameterFunctions,
            RuntimeABISpec.kFunctionFunctions,
            RuntimeABISpec.callableRefFunctions,
            RuntimeABISpec.delegateFunctions,
            RuntimeABISpec.dispatchBridgeFunctions,
            RuntimeABISpec.bitwiseFunctions,
            RuntimeABISpec.booleanFunctions,
            RuntimeABISpec.charFunctions,
            RuntimeABISpec.mathFunctions,
            RuntimeABISpec.randomFunctions,
            RuntimeABISpec.collectionFunctions,
            RuntimeABISpec.collectionBridgeFunctions,
            RuntimeABISpec.runtimeOnlyBridgeFunctions,
            RuntimeABISpec.sequenceFunctions,
            RuntimeABISpec.regexFunctions,
            RuntimeABISpec.base64Functions,
            RuntimeABISpec.hexFormatFunctions,
            RuntimeABISpec.comparatorFunctions,
            RuntimeABISpec.resultFunctions,
            RuntimeABISpec.kotlinVersionFunctions,
            RuntimeABISpec.deepRecursiveFunctions,
            RuntimeABISpec.stringBuilderFunctions,
            RuntimeABISpec.fileIOFunctions,
            RuntimeABISpec.pathFunctions,
            RuntimeABISpec.i18nFunctions,
            RuntimeABISpec.uuidFunctions,
            RuntimeABISpec.durationFunctions,
            RuntimeABISpec.timeAndPathBridgeFunctions,
            RuntimeABISpec.atomicFunctions,
            RuntimeABISpec.nativeRefFunctions,
            RuntimeABISpec.threadLocalFunctions,
            RuntimeABISpec.threadFunctions,
            RuntimeABISpec.securityFunctions,
            RuntimeABISpec.parallelFunctions,
            RuntimeABISpec.bigIntegerFunctions,
            RuntimeABISpec.broadcastChannelFunctions,
            RuntimeABISpec.serializationFunctions,
            RuntimeABISpec.networkFunctions,
            RuntimeABISpec.abiParityFunctions,
        ]
        let sectionNames = sections.flatMap { $0.map(\.name) }
        let duplicateNames = Dictionary(grouping: sectionNames, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        XCTAssertTrue(
            duplicateNames.isEmpty,
            "RuntimeABISpec section lists should not contain duplicate names: \(duplicateNames.joined(separator: ", "))"
        )
        XCTAssertEqual(
            RuntimeABISpec.allFunctions.count,
            Set(sectionNames).count
        )
    }

    func testNativeRefFunctionCount() {
        XCTAssertEqual(RuntimeABISpec.nativeRefFunctions.count, 14)
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

    func testKKThreadLocalNewSignature() throws {
        let spec = try requireSpec("kk_thread_local_new")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKThreadLocalGetOrSetSignature() throws {
        let spec = try requireSpec("kk_thread_local_getOrSet")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "receiver")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKThreadCreateSignature() throws {
        let spec = try requireSpec("kk_thread_create")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 7)
        XCTAssertEqual(spec.parameters[0].name, "start")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "isDaemon")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "contextClassLoaderRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "nameRaw")
        XCTAssertEqual(spec.parameters[3].type, .intptr)
        XCTAssertEqual(spec.parameters[4].name, "priority")
        XCTAssertEqual(spec.parameters[4].type, .intptr)
        XCTAssertEqual(spec.parameters[5].name, "fnPtr")
        XCTAssertEqual(spec.parameters[5].type, .intptr)
        XCTAssertEqual(spec.parameters[6].name, "closureRaw")
        XCTAssertEqual(spec.parameters[6].type, .intptr)
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

    func testKKFloorModSignatures() throws {
        for name in ["kk_op_floor_mod", "kk_op_lfloor_mod"] {
            let spec = try requireSpec(name)
            XCTAssertEqual(spec.returnType, .intptr)
            XCTAssertEqual(spec.parameters.map(\.type), [.intptr, .intptr])
        }
    }

    func testKKThrowablePrintStackTraceSignature() throws {
        let spec = try requireSpec("kk_throwable_printStackTrace")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKNoWhenBranchMatchedExceptionConstructorsSignature() throws {
        let noArg = try requireSpec("kk_no_when_branch_matched_exception_new")
        XCTAssertEqual(noArg.returnType, .intptr)
        XCTAssertEqual(noArg.parameters.count, 0)

        let message = try requireSpec("kk_no_when_branch_matched_exception_new_message")
        XCTAssertEqual(message.returnType, .intptr)
        XCTAssertEqual(message.parameters.map(\.type), [.intptr])

        let messageCause = try requireSpec("kk_no_when_branch_matched_exception_new_message_cause")
        XCTAssertEqual(messageCause.returnType, .intptr)
        XCTAssertEqual(messageCause.parameters.map(\.type), [.intptr, .intptr])

        let cause = try requireSpec("kk_no_when_branch_matched_exception_new_cause")
        XCTAssertEqual(cause.returnType, .intptr)
        XCTAssertEqual(cause.parameters.map(\.type), [.intptr])
    }

    func testKKConcurrentModificationExceptionConstructorsSignature() throws {
        let noArg = try requireSpec("kk_concurrent_modification_exception_new")
        XCTAssertEqual(noArg.returnType, .intptr)
        XCTAssertEqual(noArg.parameters.count, 0)

        let message = try requireSpec("kk_concurrent_modification_exception_new_message")
        XCTAssertEqual(message.returnType, .intptr)
        XCTAssertEqual(message.parameters.map(\.type), [.intptr])

        let messageCause = try requireSpec("kk_concurrent_modification_exception_new_message_cause")
        XCTAssertEqual(messageCause.returnType, .intptr)
        XCTAssertEqual(messageCause.parameters.map(\.type), [.intptr, .intptr])

        let cause = try requireSpec("kk_concurrent_modification_exception_new_cause")
        XCTAssertEqual(cause.returnType, .intptr)
        XCTAssertEqual(cause.parameters.map(\.type), [.intptr])
    }

    func testKKArrayIndexOutOfBoundsExceptionConstructorsSignature() throws {
        let noArg = try requireSpec("kk_array_index_out_of_bounds_exception_new")
        XCTAssertEqual(noArg.returnType, .intptr)
        XCTAssertEqual(noArg.parameters.count, 0)

        let message = try requireSpec("kk_array_index_out_of_bounds_exception_new_message")
        XCTAssertEqual(message.returnType, .intptr)
        XCTAssertEqual(message.parameters.map(\.type), [.intptr])
    }

    func testKKThrowableIsCancellationSignature() throws {
        let spec = try requireSpec("kk_throwable_is_cancellation")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKThrowableSuppressedExceptionsSignature() throws {
        let spec = try requireSpec("kk_throwable_suppressedExceptions")
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

    func testKKCreateCoroutineUninterceptedSignature() throws {
        let spec = try requireSpec("kk_create_coroutine_unintercepted")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "entryPointRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "completionContinuation")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
    }

    func testKKStartCoroutineUninterceptedOrReturnSignature() throws {
        let spec = try requireSpec("kk_start_coroutine_unintercepted_or_return")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "entryPointRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "continuation")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "outThrown")
        XCTAssertEqual(spec.parameters[2].type, .nullableIntptrPointer)
    }

    func testKKSuspendFunctionInvokeSignature() throws {
        let spec = try requireSpec("kk_suspend_function_invoke")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "functionRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "arg")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "outThrown")
        XCTAssertEqual(spec.parameters[2].type, .nullableIntptrPointer)
    }

    func testKKSuspendFunctionInvokeZeroAritySignature() throws {
        let spec = try requireSpec("kk_suspend_function_invoke_0")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "functionRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "outThrown")
        XCTAssertEqual(spec.parameters[1].type, .nullableIntptrPointer)
    }

    func testKKMutableListAddAtSignature() throws {
        let spec = try requireSpec("kk_mutable_list_add_at")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "index")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "element")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKMutableListSetSignature() throws {
        let spec = try requireSpec("kk_mutable_list_set")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "index")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "element")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKComparatorFromSelectorPrimitiveSignature() throws {
        let spec = try requireSpec("kk_comparator_from_selector_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .int32)
    }

    func testKKListSortedPrimitiveSignature() throws {
        let spec = try requireSpec("kk_list_sorted_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .int32)
    }

    func testKKListSortedByPrimitiveSignature() throws {
        let spec = try requireSpec("kk_list_sortedBy_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .int32)
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
    }

    func testKKListSortedByDescendingPrimitiveSignature() throws {
        let spec = try requireSpec("kk_list_sortedByDescending_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .int32)
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
    }

    func testKKMutableListSortPrimitiveSignature() throws {
        let spec = try requireSpec("kk_mutable_list_sort_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .int32)
    }

    func testKKMutableListSortByPrimitiveSignature() throws {
        let spec = try requireSpec("kk_mutable_list_sortBy_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .int32)
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
    }

    func testKKMutableListSortByDescendingPrimitiveSignature() throws {
        let spec = try requireSpec("kk_mutable_list_sortByDescending_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .int32)
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
    }

    func testKKLockWithLockSignature() throws {
        let spec = try requireSpec("kk_lock_withLock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "actionFnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "actionEnvPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
    }

    func testKKMutexCreateSignature() throws {
        let spec = try requireSpec("kk_mutex_create")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKReadWriteLockCreateSignature() throws {
        let spec = try requireSpec("kk_read_write_lock_create")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKMutexLockSignature() throws {
        let spec = try requireSpec("kk_mutex_lock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "continuation")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
    }

    func testKKMutexUnlockSignature() throws {
        let spec = try requireSpec("kk_mutex_unlock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKMutexTryLockSignature() throws {
        let spec = try requireSpec("kk_mutex_tryLock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKMutexIsLockedSignature() throws {
        let spec = try requireSpec("kk_mutex_isLocked")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKMutexWithLockSignature() throws {
        let spec = try requireSpec("kk_mutex_withLock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "actionFnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "actionEnvPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "continuation")
        XCTAssertEqual(spec.parameters[3].type, .intptr)
    }

    func testKKReadWriteLockReadSignature() throws {
        let spec = try requireSpec("kk_read_write_lock_read")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "actionFnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "actionEnvPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
    }

    func testKKReadWriteLockWriteSignature() throws {
        let spec = try requireSpec("kk_read_write_lock_write")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "actionFnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "actionEnvPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
    }

    // MARK: - Collection HOF Scan/Reduce (STDLIB-526..530)

    func testKKListReduceOrNullSignature() throws {
        let spec = try requireSpec("kk_list_reduceOrNull")
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListScanReduceSignature() throws {
        let spec = try requireSpec("kk_list_scanReduce")
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListScanSignature() throws {
        let spec = try requireSpec("kk_list_scan")
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "initial")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "fnPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "closureRaw")
        XCTAssertEqual(spec.parameters[3].type, .intptr)
        XCTAssertEqual(spec.parameters[4].name, "outThrown")
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListRunningFoldSignature() throws {
        let spec = try requireSpec("kk_list_runningFold")
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "initial")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "fnPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "closureRaw")
        XCTAssertEqual(spec.parameters[3].type, .intptr)
        XCTAssertEqual(spec.parameters[4].name, "outThrown")
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListRunningReduceSignature() throws {
        let spec = try requireSpec("kk_list_runningReduce")
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
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

    func testCDeclarationForKKGcSchedule() throws {
        let spec = try requireSpec("kk_gc_schedule")
        XCTAssertEqual(spec.cDeclaration, "intptr_t kk_gc_schedule(void);")
    }

    func testCDeclarationForKKGcTargetHeapUtilization() throws {
        let spec = try requireSpec("kk_gc_target_heap_utilization")
        XCTAssertEqual(spec.cDeclaration, "double kk_gc_target_heap_utilization(void);")
    }

    func testCDeclarationForKKDebuggingGlobalObjectCount() throws {
        let spec = try requireSpec("kk_debugging_global_object_count")
        XCTAssertEqual(spec.cDeclaration, "intptr_t kk_debugging_global_object_count(void);")
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
        XCTAssertTrue(header.contains("Print"))
        XCTAssertTrue(header.contains("GC"))
        XCTAssertTrue(header.contains("Coroutine"))
        XCTAssertTrue(header.contains("Boxing"))
        XCTAssertTrue(header.contains("Array"))
        XCTAssertTrue(header.contains("TypeCheck"))
        XCTAssertTrue(header.contains("Bitwise"))
    }
}
