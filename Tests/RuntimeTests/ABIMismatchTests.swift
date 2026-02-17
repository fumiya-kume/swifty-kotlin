import XCTest
@testable import Runtime

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
        // kk_string_from_utf8, kk_string_concat
        XCTAssertEqual(RuntimeABISpec.stringFunctions.count, 2)
    }

    func testPrintlnFunctionCount() {
        // kk_println_any
        XCTAssertEqual(RuntimeABISpec.printlnFunctions.count, 1)
    }

    func testCoroutineFunctionCount() {
        // kk_coroutine_suspended
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

    func testKKAllocSignature() throws {
        let spec = try requireSpec("kk_alloc")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "size")
        XCTAssertEqual(spec.parameters[0].type, .uint32)
        XCTAssertEqual(spec.parameters[1].name, "typeInfo")
        XCTAssertEqual(spec.parameters[1].type, .opaquePointer)
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
            "void * kk_alloc(uint32_t size, void * typeInfo);"
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
        XCTAssertTrue(header.contains("Coroutine"))
    }
}
