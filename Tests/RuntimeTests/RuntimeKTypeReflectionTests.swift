@testable import Runtime
import Foundation
import Testing

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

@Suite(.serialized, .runtimeIsolation(.gcAndMetadata))
struct RuntimeKTypeReflectionTests {
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

    private func makeRuntimeString(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func kk_println_any(_ value: Int) {
        __kk_print_raw(makeRuntimeString(runtimeRenderAnyForPrint(value) + "\n"))
    }

    private func kk_println_any(_ value: UnsafeMutableRawPointer?) {
        kk_println_any(Int(bitPattern: value))
    }

    private func registerKClassMetadata(typeToken: Int, qualifiedName: String, simpleName: String) {
        let qualifiedNameRaw = makeRuntimeString(qualifiedName)
        let simpleNameRaw = makeRuntimeString(simpleName)
        let result = __kk_kclass_register_metadata(typeToken, qualifiedNameRaw, simpleNameRaw, 0, 0, -1, -1, 0)
        #expect(result == 0)
    }

    private func makeKClassHandle(name: String, typeToken: Int) -> Int {
        let simpleName = name.split(separator: ".").last.map(String.init) ?? name
        registerKClassMetadata(typeToken: typeToken, qualifiedName: name, simpleName: simpleName)
        return __kk_kclass_create(typeToken, 0)
    }

    private func makeKTypeProjectionHandle(type: Int, variance: Int = 2) -> Int {
        __kk_ktypeprojection_create(type, variance)
    }

    private func makeKTypeHandle(
        name: String,
        typeToken: Int,
        arguments: [Int] = [],
        isNullable: Bool = false
    ) -> Int {
        _ = makeKClassHandle(name: name, typeToken: typeToken)
        let argsRaw: Int
        if arguments.isEmpty {
            argsRaw = 0
        } else {
            let array = kk_array_new(arguments.count)
            var thrown = 0
            for (index, argument) in arguments.enumerated() {
                _ = kk_array_set(array, index, argument, &thrown)
                #expect(thrown == 0)
            }
            argsRaw = kk_list_of(array, arguments.count)
        }
        return kk_typeof(typeToken, 0, argsRaw, isNullable ? 1 : 0)
    }

    @Test func ktypeAccessorsRoundTripBasicTypes() {
        let stringType = makeKTypeHandle(name: "kotlin.String", typeToken: 2)
        let nullableIntType = makeKTypeHandle(name: "kotlin.Int", typeToken: 3, isNullable: true)

        #expect(__kk_ktype_isMarkedNullable(stringType) == 0)
        #expect(__kk_ktype_isMarkedNullable(nullableIntType) == 1)

        let stringClassifier = __kk_ktype_classifier(stringType)
        #expect(stringClassifier != runtimeNullSentinelInt)
        #expect(runtimeListBox(from: __kk_ktype_arguments(stringType))?.elements.count == 0)
    }

    @Test func ktypeToStringRendersGenericArgumentsAndNullability() {
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

        #expect(runtimeRenderAnyForPrint(stringType) == "kotlin.String")
        #expect(runtimeRenderAnyForPrint(nullableStringType) == "kotlin.String?")
        #expect(runtimeRenderAnyForPrint(listType) == "kotlin.collections.List<kotlin.String>")
        #expect(runtimeRenderAnyForPrint(arrayType) == "kotlin.Array<kotlin.String>")
        #expect(
            runtimeRenderAnyForPrint(nestedType)
                == "kotlin.collections.Map<kotlin.String, kotlin.collections.List<kotlin.String?>>"
        )
    }

    @Test func ktypeArgumentsExposeKTypeProjectionsAndStar() {
        let elementType = makeKTypeHandle(name: "kotlin.Int", typeToken: 20)
        let projection = __kk_ktypeprojection_create(elementType, 2)
        let starProjection = __kk_ktypeprojection_create(0, -1)
        let arrayType = makeKTypeHandle(name: "kotlin.Array", typeToken: 21, arguments: [projection])

        #expect(runtimeRenderAnyForPrint(projection) == "kotlin.Int")
        #expect(runtimeRenderAnyForPrint(starProjection) == "*")

        let argumentsRaw = __kk_ktype_arguments(arrayType)
        let arguments = runtimeListBox(from: argumentsRaw)
        #expect(arguments?.elements.count == 1)
        #expect(arguments?.elements.first == projection)
        #expect(runtimeRenderAnyForPrint(arrayType) == "kotlin.Array<kotlin.Int>")
        #expect(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: argumentsRaw)) } == "[kotlin.Int]")
    }

    @Test func ktypeBoxesRegisterSourceBackedPropertyGetters() throws {
        let elementType = makeKTypeHandle(name: "kotlin.Int", typeToken: 30)
        let projection = __kk_ktypeprojection_create(elementType, 2)
        let listType = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 31,
            arguments: [projection]
        )
        let interfaceTypeID = Int(runtimeStableNominalTypeID(fqName: "kotlin.reflect.KType"))
        let getterType = (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self

        let argumentsGetterRaw = kk_itable_lookup_dynamic(listType, interfaceTypeID, 0)
        let classifierGetterRaw = kk_itable_lookup_dynamic(listType, interfaceTypeID, 1)
        let nullableGetterRaw = kk_itable_lookup_dynamic(listType, interfaceTypeID, 2)
        #expect(argumentsGetterRaw != 0)
        #expect(classifierGetterRaw != 0)
        #expect(nullableGetterRaw != 0)

        let argumentsGetter = unsafeBitCast(argumentsGetterRaw, to: getterType)
        let classifierGetter = unsafeBitCast(classifierGetterRaw, to: getterType)
        let nullableGetter = unsafeBitCast(nullableGetterRaw, to: getterType)
        var thrown = 0
        let argumentsRaw = argumentsGetter(listType, &thrown)
        #expect(thrown == 0)
        #expect(runtimeListBox(from: argumentsRaw)?.elements == [projection])
        #expect(classifierGetter(listType, &thrown) == __kk_ktype_classifier(listType))
        #expect(nullableGetter(listType, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test func invalidHandlesReturnSentinels() {
        #expect(__kk_ktype_classifier(123_456) == runtimeNullSentinelInt)
        #expect(runtimeListBox(from: __kk_ktype_arguments(123_456))?.elements.count == 0)
        #expect(__kk_ktype_isMarkedNullable(123_456) == 0)
    }
}
