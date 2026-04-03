@testable import Runtime
import XCTest

final class RuntimeMetadataAPITests: IsolatedRuntimeXCTestCase {
    private func makeRuntimeString(_ value: String) -> Int {
        value.withCString { cString in
            cString.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    func testMetadataSerializationRoundTrip() throws {
        let metadata = KotlinMetadata(
            functions: [
                KmFunction(
                    name: "greet",
                    returnType: "kotlin.String",
                    valueParameters: [
                        KmValueParameter(name: "name", type: "kotlin.String")
                    ],
                    annotations: [
                        KmAnnotation(className: "sample.Logged", arguments: ["level=debug"])
                    ],
                    isSuspend: false,
                    typeSignature: "(kotlin.String) -> kotlin.String"
                )
            ],
            constructors: [
                KmConstructor(
                    valueParameters: [
                        KmValueParameter(name: "name", type: "kotlin.String")
                    ],
                    annotations: [
                        KmAnnotation(className: "sample.Inject")
                    ],
                    isPrimary: true,
                    visibility: "PUBLIC",
                    declaringClassName: "sample.Greeter"
                )
            ],
            annotations: [
                KmAnnotation(className: "sample.FileAnno", arguments: ["enabled=true"])
            ],
            compilerPlugins: [
                compilerPluginMetadata(
                    pluginId: "sample.plugin",
                    version: "1.2.3",
                    data: ["mode": "strict"]
                )
            ]
        )

        let serialized = try RuntimeMetadataCodec.serialize(metadata)
        let decoded = try RuntimeMetadataCodec.deserialize(serialized)

        XCTAssertEqual(decoded, metadata)
        XCTAssertTrue(serialized.contains("\"pluginId\":\"sample.plugin\""))
    }

    func testDeserializeRejectsInvalidJSON() {
        XCTAssertThrowsError(try RuntimeMetadataCodec.deserialize("{not-json}")) { error in
            guard case let RuntimeMetadataCodec.Error.decodingFailed(message) = error else {
                return XCTFail("Expected decodingFailed error, got: \(error)")
            }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testKmFunctionCanBeBuiltFromRuntimeBoxes() {
        let parameterRaw = kk_kparameter_create(
            0,
            makeRuntimeString("value"),
            makeRuntimeString("kotlin.Int"),
            1,
            2
        )
        let parameterList = registerRuntimeObject(RuntimeListBox(elements: [parameterRaw]))
        let functionRaw = kk_kfunction_create_full(
            makeRuntimeString("plusOne"),
            1,
            makeRuntimeString("kotlin.Int"),
            0,
            0,
            0,
            parameterList,
            makeRuntimeString("(kotlin.Int) -> kotlin.Int")
        )

        guard let functionBox = runtimeObject(functionRaw, as: RuntimeKFunctionBox.self) else {
            return XCTFail("Expected RuntimeKFunctionBox")
        }

        let metadata = KmFunction(functionBox, annotations: [KmAnnotation(className: "sample.Test")])
        XCTAssertEqual(metadata.name, "plusOne")
        XCTAssertEqual(metadata.returnType, "kotlin.Int")
        XCTAssertEqual(metadata.valueParameters.count, 1)
        XCTAssertEqual(metadata.valueParameters.first?.name, "value")
        XCTAssertTrue(metadata.valueParameters.first?.isOptional == true)
        XCTAssertEqual(metadata.typeSignature, "(kotlin.Int) -> kotlin.Int")
        XCTAssertEqual(metadata.annotations.map(\.className), ["sample.Test"])
    }

    func testKmConstructorCanBeBuiltFromRuntimeBoxes() {
        let classEntry = RuntimeKClassMetadataEntry(
            qualifiedName: "sample.Person",
            simpleName: "Person",
            supertypeName: nil,
            isDataClass: true,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 2,
            memberCount: 3,
            constructorCount: 1,
            isFinal: true,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        runtimeKClassMetadataRegistry.register(typeToken: 501, entry: classEntry)
        let kclassRaw = kk_kclass_create(501, makeRuntimeString("Person"))

        let box = RuntimeKConstructorBox(
            nameRaw: makeRuntimeString("<init>"),
            arity: 2,
            returnTypeRaw: makeRuntimeString("sample.Person"),
            fnPtr: 0,
            isPrimary: true,
            visibilityRaw: makeRuntimeString("PUBLIC"),
            declaringClassRaw: kclassRaw,
            parameterNameRaws: [makeRuntimeString("name"), makeRuntimeString("age")]
        )

        let metadata = KmConstructor(box, annotations: [KmAnnotation(className: "sample.Inject")])
        XCTAssertEqual(metadata.name, "<init>")
        XCTAssertEqual(metadata.declaringClassName, "sample.Person")
        XCTAssertEqual(metadata.valueParameters.map(\.name), ["name", "age"])
        XCTAssertEqual(metadata.visibility, "PUBLIC")
        XCTAssertTrue(metadata.isPrimary)
        XCTAssertEqual(metadata.annotations.map(\.className), ["sample.Inject"])
    }

    private func runtimeObject<T: AnyObject>(_ raw: Int, as type: T.Type) -> T? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return nil
        }
        return tryCast(ptr, to: type)
    }
}
