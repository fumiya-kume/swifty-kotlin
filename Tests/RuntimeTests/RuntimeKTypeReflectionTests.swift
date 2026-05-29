@testable import Runtime
import XCTest

final class RuntimeKTypeReflectionTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcAndMetadata }
    private func capturePrintln(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(STDOUT_FILENO)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        block()
        fflush(nil)
        dup2(savedFD, STDOUT_FILENO)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func boolValue(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeBoolBox.self)
        else {
            return false
        }
        return box.value
    }

    private func makeRuntimeString(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func registerKClassMetadata(typeToken: Int, qualifiedName: String, simpleName: String) {
        let qualifiedNameRaw = makeRuntimeString(qualifiedName)
        let simpleNameRaw = makeRuntimeString(simpleName)
        let result = kk_kclass_register_metadata(typeToken, qualifiedNameRaw, simpleNameRaw, 0, 0, -1, -1, 0)
        XCTAssertEqual(result, 0)
    }

    private func makeKClassHandle(name: String, typeToken: Int) -> Int {
        let simpleName = name.split(separator: ".").last.map(String.init) ?? name
        registerKClassMetadata(typeToken: typeToken, qualifiedName: name, simpleName: simpleName)
        return kk_kclass_create(typeToken, 0)
    }

    private func makeKTypeProjectionHandle(type: Int, variance: Int = 2) -> Int {
        kk_ktypeprojection_create(type, variance)
    }

    private func makeKTypeHandle(
        name: String,
        typeToken: Int,
        arguments: [Int] = [],
        isNullable: Bool = false
    ) -> Int {
        let kclass = makeKClassHandle(name: name, typeToken: typeToken)
        let argsRaw: Int
        if arguments.isEmpty {
            argsRaw = 0
        } else {
            let array = kk_array_new(arguments.count)
            var thrown = 0
            for (index, argument) in arguments.enumerated() {
                _ = kk_array_set(array, index, argument, &thrown)
                XCTAssertEqual(thrown, 0)
            }
            argsRaw = kk_list_of(array, arguments.count)
        }
        return kk_ktype_create(kclass, argsRaw, isNullable ? 1 : 0)
    }

    func testKTypeAccessorsRoundTripBasicTypes() {
        let stringType = makeKTypeHandle(name: "kotlin.String", typeToken: 2)
        let nullableIntType = makeKTypeHandle(name: "kotlin.Int", typeToken: 3, isNullable: true)

        XCTAssertEqual(kk_ktype_isMarkedNullable(stringType), 0)
        XCTAssertEqual(kk_ktype_isMarkedNullable(nullableIntType), 1)

        let stringClassifier = kk_ktype_classifier(stringType)
        XCTAssertNotEqual(stringClassifier, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeListBox(from: kk_ktype_arguments(stringType))?.elements.count, 0)
    }

    func testKTypeToStringRendersGenericArgumentsAndNullability() {
        let stringType = makeKTypeHandle(name: "kotlin.String", typeToken: 10)
        let nullableStringType = makeKTypeHandle(name: "kotlin.String", typeToken: 11, isNullable: true)
        let listType = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 12,
            arguments: [makeKTypeProjectionHandle(type: stringType)]
        )
        let arrayType = makeKTypeHandle(
            name: "kotlin.Array",
            typeToken: 13,
            arguments: [makeKTypeProjectionHandle(type: stringType)]
        )
        let nestedType = makeKTypeHandle(
            name: "kotlin.collections.Map",
            typeToken: 14,
            arguments: [
                makeKTypeProjectionHandle(type: stringType),
                makeKTypeProjectionHandle(
                    type: makeKTypeHandle(
                        name: "kotlin.collections.List",
                        typeToken: 15,
                        arguments: [makeKTypeProjectionHandle(type: nullableStringType)]
                    )
                ),
            ]
        )

        XCTAssertEqual(runtimeStringValue(kk_ktype_to_string(stringType)), "kotlin.String")
        XCTAssertEqual(runtimeStringValue(kk_ktype_to_string(nullableStringType)), "kotlin.String?")
        XCTAssertEqual(runtimeStringValue(kk_ktype_to_string(listType)), "kotlin.collections.List<kotlin.String>")
        XCTAssertEqual(runtimeStringValue(kk_ktype_to_string(arrayType)), "kotlin.Array<kotlin.String>")
        XCTAssertEqual(
            runtimeStringValue(kk_ktype_to_string(nestedType)),
            "kotlin.collections.Map<kotlin.String, kotlin.collections.List<kotlin.String?>>"
        )
    }

    func testKTypeArgumentsExposeKTypeProjectionsAndStar() {
        let elementType = makeKTypeHandle(name: "kotlin.Int", typeToken: 20)
        let projection = kk_ktypeprojection_create(elementType, 2)
        let starProjection = kk_ktypeprojection_create(0, -1)
        let arrayType = makeKTypeHandle(name: "kotlin.Array", typeToken: 21, arguments: [projection])

        XCTAssertEqual(kk_ktypeprojection_type(projection), elementType)
        XCTAssertEqual(kk_ktypeprojection_variance(projection), 2)
        XCTAssertEqual(kk_ktypeprojection_type(starProjection), runtimeNullSentinelInt)
        XCTAssertEqual(kk_ktypeprojection_variance(starProjection), -1)

        let argumentsRaw = kk_ktype_arguments(arrayType)
        let arguments = runtimeListBox(from: argumentsRaw)
        XCTAssertEqual(arguments?.elements.count, 1)
        XCTAssertEqual(arguments?.elements.first, projection)
        XCTAssertEqual(runtimeStringValue(kk_ktype_to_string(arrayType)), "kotlin.Array<kotlin.Int>")
        XCTAssertEqual(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: argumentsRaw)) }, "[kotlin.Int]")
    }

    func testKTypeEqualityAndHashCodeAreStructural() {
        let stringTypeA = makeKTypeHandle(name: "kotlin.String", typeToken: 30)
        let stringTypeB = makeKTypeHandle(name: "kotlin.String", typeToken: 30)
        let nullableStringType = makeKTypeHandle(name: "kotlin.String", typeToken: 30, isNullable: true)
        let listTypeA = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 31,
            arguments: [makeKTypeProjectionHandle(type: stringTypeA)]
        )
        let listTypeB = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 31,
            arguments: [makeKTypeProjectionHandle(type: stringTypeB)]
        )
        let outListType = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 31,
            arguments: [makeKTypeProjectionHandle(type: stringTypeB, variance: 1)]
        )

        XCTAssertNotEqual(stringTypeA, stringTypeB)
        XCTAssertTrue(boolValue(kk_ktype_equals(stringTypeA, stringTypeB)))
        XCTAssertTrue(boolValue(kk_ktype_equals(listTypeA, listTypeB)))
        XCTAssertEqual(kk_structural_eq(listTypeA, listTypeB), 1)
        XCTAssertEqual(kk_ktype_hashCode(listTypeA), kk_ktype_hashCode(listTypeB))
        XCTAssertEqual(kk_any_hashCode(listTypeA, 0), kk_any_hashCode(listTypeB, 0))
        XCTAssertFalse(boolValue(kk_ktype_equals(stringTypeA, nullableStringType)))
        XCTAssertFalse(boolValue(kk_ktype_equals(listTypeA, outListType)))
        XCTAssertFalse(boolValue(kk_ktype_equals(listTypeA, stringTypeA)))
        XCTAssertFalse(boolValue(kk_ktype_equals(123456, 123456)))
        XCTAssertEqual(kk_ktype_hashCode(123456), 0)
    }

    func testInvalidHandlesReturnSentinels() {
        XCTAssertEqual(kk_ktype_classifier(123456), runtimeNullSentinelInt)
        XCTAssertEqual(runtimeListBox(from: kk_ktype_arguments(123456))?.elements.count, 0)
        XCTAssertEqual(kk_ktype_isMarkedNullable(123456), 0)
        XCTAssertEqual(kk_ktypeprojection_type(123456), runtimeNullSentinelInt)
        XCTAssertEqual(kk_ktypeprojection_variance(123456), -1)
        XCTAssertEqual(runtimeStringValue(kk_ktype_to_string(123456)), "kotlin.Any")
    }
}
