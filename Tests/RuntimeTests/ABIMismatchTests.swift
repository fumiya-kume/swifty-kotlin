import XCTest
@testable import Runtime
import CompilerCore

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
        // kk_throwable_new, kk_panic
        XCTAssertEqual(RuntimeABISpec.exceptionFunctions.count, 2)
    }

    func testStringFunctionCount() {
        // kk_string_from_utf8, kk_string_concat, kk_string_compareTo
        XCTAssertEqual(RuntimeABISpec.stringFunctions.count, 3)
    }

    func testPrintlnFunctionCount() {
        // kk_println_any
        XCTAssertEqual(RuntimeABISpec.printlnFunctions.count, 1)
    }

    func testGCFunctionCount() {
        // kk_register_global_root, kk_unregister_global_root,
        // kk_register_frame_map, kk_push_frame, kk_pop_frame,
        // kk_register_coroutine_root, kk_unregister_coroutine_root,
        // kk_runtime_heap_object_count, kk_runtime_force_reset
        XCTAssertEqual(RuntimeABISpec.gcFunctions.count, 9)
    }

    func testCoroutineFunctionCount() {
        // 19 base coroutine functions + 12 consolidated stubs (Flow/Dispatchers/Channel/awaitAll)
        XCTAssertEqual(RuntimeABISpec.coroutineFunctions.count, 31)
    }

    func testBoxingFunctionCount() {
        // kk_box_int, kk_box_bool, kk_unbox_int, kk_unbox_bool
        XCTAssertEqual(RuntimeABISpec.boxingFunctions.count, 4)
    }

    func testArrayFunctionCount() {
        // kk_array_new, kk_array_get, kk_array_set, kk_vararg_spread_concat
        XCTAssertEqual(RuntimeABISpec.arrayFunctions.count, 4)
    }

    func testTotalFunctionCount() {
        let expected = RuntimeABISpec.memoryFunctions.count
            + RuntimeABISpec.exceptionFunctions.count
            + RuntimeABISpec.stringFunctions.count
            + RuntimeABISpec.printlnFunctions.count
            + RuntimeABISpec.gcFunctions.count
            + RuntimeABISpec.coroutineFunctions.count
            + RuntimeABISpec.boxingFunctions.count
            + RuntimeABISpec.arrayFunctions.count
            + RuntimeABISpec.rangeFunctions.count
            + RuntimeABISpec.delegateFunctions.count
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
    }

    // MARK: - Cross-Module ABI Reconciliation (Runtime <-> CompilerCore)

    /// Verify that RuntimeABISpec and RuntimeABIExterns have the same function count.
    func testExternCountMatchesSpec() {
        let specNames = RuntimeABISpec.allFunctions.map(\.name)
        let externNames = RuntimeABIExterns.allExterns.map(\.name)
        XCTAssertEqual(
            specNames.count,
            externNames.count,
            "RuntimeABISpec has \(specNames.count) functions but RuntimeABIExterns has \(externNames.count)"
        )
    }

    /// Verify that every RuntimeABISpec function has a matching RuntimeABIExterns entry.
    func testEverySpecFunctionHasMatchingExtern() {
        for spec in RuntimeABISpec.allFunctions {
            let externDecl = RuntimeABIExterns.externDecl(named: spec.name)
            XCTAssertNotNil(
                externDecl,
                "RuntimeABISpec function '\(spec.name)' has no matching entry in RuntimeABIExterns"
            )
        }
    }

    /// Verify that every RuntimeABIExterns entry has a matching RuntimeABISpec function.
    func testEveryExternHasMatchingSpecFunction() {
        for externDecl in RuntimeABIExterns.allExterns {
            let spec = RuntimeABISpec.allFunctions.first { $0.name == externDecl.name }
            XCTAssertNotNil(
                spec,
                "RuntimeABIExterns entry '\(externDecl.name)' has no matching entry in RuntimeABISpec"
            )
        }
    }

    /// Verify that function names appear in the same order in both lists.
    func testFunctionOrderMatches() {
        let specNames = RuntimeABISpec.allFunctions.map(\.name)
        let externNames = RuntimeABIExterns.allExterns.map(\.name)
        XCTAssertEqual(
            specNames,
            externNames,
            "Function order in RuntimeABISpec and RuntimeABIExterns must match"
        )
    }

    /// The core ABI mismatch detection: verify return types match.
    func testReturnTypesMatch() {
        for spec in RuntimeABISpec.allFunctions {
            guard let externDecl = RuntimeABIExterns.externDecl(named: spec.name) else {
                continue
            }
            XCTAssertEqual(
                spec.returnTypeString,
                externDecl.returnType,
                "Return type mismatch for '\(spec.name)': " +
                "RuntimeABISpec says '\(spec.returnTypeString)' but " +
                "RuntimeABIExterns says '\(externDecl.returnType)'"
            )
        }
    }

    /// The core ABI mismatch detection: verify parameter types match.
    func testParameterTypesMatch() {
        for spec in RuntimeABISpec.allFunctions {
            guard let externDecl = RuntimeABIExterns.externDecl(named: spec.name) else {
                continue
            }
            XCTAssertEqual(
                spec.parameterTypeStrings,
                externDecl.parameterTypes,
                "Parameter type mismatch for '\(spec.name)': " +
                "RuntimeABISpec says \(spec.parameterTypeStrings) but " +
                "RuntimeABIExterns says \(externDecl.parameterTypes)"
            )
        }
    }

    /// Verify parameter count match for each function.
    func testParameterCountsMatch() {
        for spec in RuntimeABISpec.allFunctions {
            guard let externDecl = RuntimeABIExterns.externDecl(named: spec.name) else {
                continue
            }
            XCTAssertEqual(
                spec.parameters.count,
                externDecl.parameterTypes.count,
                "Parameter count mismatch for '\(spec.name)': " +
                "RuntimeABISpec has \(spec.parameters.count) but " +
                "RuntimeABIExterns has \(externDecl.parameterTypes.count)"
            )
        }
    }
}
