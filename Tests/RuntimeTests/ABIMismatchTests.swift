import XCTest
@testable import Runtime

final class ABIMismatchTests: XCTestCase {

    // MARK: - Spec Integrity

    func testSpecVersionIsNonEmpty() {
        XCTAssertFalse(RuntimeABISpec.specVersion.isEmpty)
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
        XCTAssertEqual(RuntimeABISpec.memoryFunctions.count, 3)
    }

    func testExceptionFunctionCount() {
        XCTAssertEqual(RuntimeABISpec.exceptionFunctions.count, 2)
    }

    func testStringFunctionCount() {
        XCTAssertEqual(RuntimeABISpec.stringFunctions.count, 2)
    }

    func testPrintlnFunctionCount() {
        XCTAssertEqual(RuntimeABISpec.printlnFunctions.count, 1)
    }

    func testCoroutineFunctionCount() {
        XCTAssertEqual(RuntimeABISpec.coroutineFunctions.count, 1)
    }

    func testTotalFunctionCount() {
        let expected = RuntimeABISpec.memoryFunctions.count
            + RuntimeABISpec.exceptionFunctions.count
            + RuntimeABISpec.stringFunctions.count
            + RuntimeABISpec.printlnFunctions.count
            + RuntimeABISpec.coroutineFunctions.count
        XCTAssertEqual(RuntimeABISpec.allFunctions.count, expected)
    }

    // MARK: - J16.1 Signature Verification

    func testKKAllocSignature() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_alloc" }) else {
            XCTFail("kk_alloc not found in spec")
            return
        }
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "size")
        XCTAssertEqual(spec.parameters[0].type, .uint32)
        XCTAssertEqual(spec.parameters[1].name, "typeInfo")
        XCTAssertEqual(spec.parameters[1].type, .opaquePointer)
    }

    func testKKGcCollectSignature() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_gc_collect" }) else {
            XCTFail("kk_gc_collect not found in spec")
            return
        }
        XCTAssertEqual(spec.returnType, .void)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKWriteBarrierSignature() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_write_barrier" }) else {
            XCTFail("kk_write_barrier not found in spec")
            return
        }
        XCTAssertEqual(spec.returnType, .void)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .opaquePointer)
        XCTAssertEqual(spec.parameters[1].type, .fieldAddrPointer)
    }

    func testKKThrowableNewSignature() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_throwable_new" }) else {
            XCTFail("kk_throwable_new not found in spec")
            return
        }
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .nullableOpaquePointer)
    }

    func testKKPanicSignature() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_panic" }) else {
            XCTFail("kk_panic not found in spec")
            return
        }
        XCTAssertEqual(spec.returnType, .noreturn)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .constCCharPointer)
    }

    func testKKStringFromUTF8Signature() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_string_from_utf8" }) else {
            XCTFail("kk_string_from_utf8 not found in spec")
            return
        }
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .constUInt8Pointer)
        XCTAssertEqual(spec.parameters[1].type, .int32)
    }

    func testKKStringConcatSignature() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_string_concat" }) else {
            XCTFail("kk_string_concat not found in spec")
            return
        }
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .nullableOpaquePointer)
        XCTAssertEqual(spec.parameters[1].type, .nullableOpaquePointer)
    }

    func testKKPrintlnAnySignature() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_println_any" }) else {
            XCTFail("kk_println_any not found in spec")
            return
        }
        XCTAssertEqual(spec.returnType, .void)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .nullableOpaquePointer)
    }

    func testKKCoroutineSuspendedSignature() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_coroutine_suspended" }) else {
            XCTFail("kk_coroutine_suspended not found in spec")
            return
        }
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    // MARK: - C Declaration Generation

    func testCDeclarationForKKAlloc() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_alloc" }) else {
            XCTFail("kk_alloc not found in spec")
            return
        }
        XCTAssertEqual(
            spec.cDeclaration,
            "void * kk_alloc(uint32_t size, void * typeInfo);"
        )
    }

    func testCDeclarationForKKGcCollect() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_gc_collect" }) else {
            XCTFail("kk_gc_collect not found in spec")
            return
        }
        XCTAssertEqual(spec.cDeclaration, "void kk_gc_collect(void);")
    }

    func testCDeclarationForKKPrintlnAny() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_println_any" }) else {
            XCTFail("kk_println_any not found in spec")
            return
        }
        XCTAssertEqual(
            spec.cDeclaration,
            "void kk_println_any(void * _Nullable obj);"
        )
    }

    func testCDeclarationForKKPanic() {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_panic" }) else {
            XCTFail("kk_panic not found in spec")
            return
        }
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
        XCTAssertTrue(header.contains("Coroutine"))
    }
}
