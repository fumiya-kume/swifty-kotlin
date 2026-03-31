@testable import Runtime
import XCTest

/// Tests for REFL-004: KClass binary metadata registry and accessors.
final class RuntimeKClassMetadataTests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - RuntimeKClassMetadataEntry

    func testMetadataEntryStoresAllFields() {
        let entry = RuntimeKClassMetadataEntry(
            qualifiedName: "com.example.Foo",
            simpleName: "Foo",
            supertypeName: "com.example.Base",
            isDataClass: true,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 3,
            memberCount: 7,
            constructorCount: 0,
            isFinal: false,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        XCTAssertEqual(entry.qualifiedName, "com.example.Foo")
        XCTAssertEqual(entry.simpleName, "Foo")
        XCTAssertEqual(entry.supertypeName, "com.example.Base")
        XCTAssertTrue(entry.isDataClass)
        XCTAssertFalse(entry.isSealedClass)
        XCTAssertEqual(entry.fieldCount, 3)
        XCTAssertEqual(entry.memberCount, 7)
    }

    // MARK: - RuntimeKClassMetadataRegistry

    func testRegistryLookupReturnsNilForUnregisteredToken() {
        let result = runtimeKClassMetadataRegistry.lookup(typeToken: 999)
        XCTAssertNil(result)
    }

    func testRegistryRegisterAndLookup() {
        let entry = RuntimeKClassMetadataEntry(
            qualifiedName: "test.MyClass",
            simpleName: "MyClass",
            supertypeName: nil,
            isDataClass: false,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 2,
            memberCount: 5,
            constructorCount: 0,
            isFinal: true,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        runtimeKClassMetadataRegistry.register(typeToken: 42, entry: entry)
        let result = runtimeKClassMetadataRegistry.lookup(typeToken: 42)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.qualifiedName, "test.MyClass")
        XCTAssertEqual(result?.simpleName, "MyClass")
        XCTAssertNil(result?.supertypeName)
        XCTAssertEqual(result?.fieldCount, 2)
    }

    func testRegistryResetClearsEntries() {
        let entry = RuntimeKClassMetadataEntry(
            qualifiedName: "test.Temp",
            simpleName: "Temp",
            supertypeName: nil,
            isDataClass: false,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 0,
            memberCount: 0,
            constructorCount: 0,
            isFinal: false,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        runtimeKClassMetadataRegistry.register(typeToken: 100, entry: entry)
        XCTAssertNotNil(runtimeKClassMetadataRegistry.lookup(typeToken: 100))

        runtimeKClassMetadataRegistry.reset()
        XCTAssertNil(runtimeKClassMetadataRegistry.lookup(typeToken: 100))
    }

    // MARK: - RuntimeKClassBox Metadata Property

    func testKClassBoxMetadataReturnsNilWithoutRegistration() {
        let box = RuntimeKClassBox(typeToken: 77, nameHint: 0)
        XCTAssertNil(box.metadata)
    }

    func testKClassBoxMetadataReturnsRegisteredEntry() {
        let entry = RuntimeKClassMetadataEntry(
            qualifiedName: "pkg.Widget",
            simpleName: "Widget",
            supertypeName: "pkg.Base",
            isDataClass: true,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 4,
            memberCount: 6,
            constructorCount: 0,
            isFinal: true,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        runtimeKClassMetadataRegistry.register(typeToken: 77, entry: entry)
        let box = RuntimeKClassBox(typeToken: 77, nameHint: 0)
        XCTAssertNotNil(box.metadata)
        XCTAssertEqual(box.metadata?.qualifiedName, "pkg.Widget")
        XCTAssertTrue(box.metadata?.isDataClass ?? false)
    }

    // MARK: - kk_kclass_register_metadata C API

    func testRegisterMetadataViaCABI() {
        // Create runtime strings for names.
        let qualifiedName = makeRuntimeString("com.example.Animal")
        let simpleName = makeRuntimeString("Animal")
        let supertypeName = makeRuntimeString("com.example.LivingThing")

        // flags: dataClass=1 (bit 0), abstract=1 (bit 7)
        let flags = (1 << 0) | (1 << 7) // 0b10000001 = 129

        let result = kk_kclass_register_metadata(
            42, // typeToken
            qualifiedName,
            simpleName,
            supertypeName,
            flags,
            5, // fieldCount
            12, // memberCount
            2 // constructorCount
        )
        XCTAssertEqual(result, 0)

        let entry = runtimeKClassMetadataRegistry.lookup(typeToken: 42)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.qualifiedName, "com.example.Animal")
        XCTAssertEqual(entry?.simpleName, "Animal")
        XCTAssertEqual(entry?.supertypeName, "com.example.LivingThing")
        XCTAssertTrue(entry?.isDataClass ?? false)
        XCTAssertTrue(entry?.isAbstract ?? false)
        XCTAssertFalse(entry?.isSealedClass ?? true)
        XCTAssertEqual(entry?.fieldCount, 5)
        XCTAssertEqual(entry?.memberCount, 12)
        XCTAssertEqual(entry?.constructorCount, 2)
    }

    func testRegisterMetadataWithNullSupertype() {
        let qualifiedName = makeRuntimeString("Simple")
        let simpleName = makeRuntimeString("Simple")

        let _ = kk_kclass_register_metadata(
            99, qualifiedName, simpleName,
            0, // null supertype
            0, // no flags
            1, -1, 0 // fieldCount=1, memberCount unknown, constructorCount=0
        )

        let entry = runtimeKClassMetadataRegistry.lookup(typeToken: 99)
        XCTAssertNotNil(entry)
        XCTAssertNil(entry?.supertypeName)
        XCTAssertFalse(entry?.isDataClass ?? true)
    }

    // MARK: - KClass Accessor Functions

    func testKClassIsDataReturnsCorrectValue() {
        let typeToken = 200
        registerTestMetadata(typeToken: typeToken, flags: 1 << 0) // dataClass
        let kclass = kk_kclass_create(typeToken, 0)
        XCTAssertEqual(kk_kclass_is_data(kclass), 1)
    }

    func testKClassIsDataReturnsFalseWhenNotData() {
        let typeToken = 201
        registerTestMetadata(typeToken: typeToken, flags: 0)
        let kclass = kk_kclass_create(typeToken, 0)
        XCTAssertEqual(kk_kclass_is_data(kclass), 0)
    }

    func testKClassIsSealedReturnsCorrectValue() {
        let typeToken = 202
        registerTestMetadata(typeToken: typeToken, flags: 1 << 1) // sealedClass
        let kclass = kk_kclass_create(typeToken, 0)
        XCTAssertEqual(kk_kclass_is_sealed(kclass), 1)
    }

    func testKClassIsValueReturnsCorrectValue() {
        let typeToken = 203
        registerTestMetadata(typeToken: typeToken, flags: 1 << 2) // valueClass
        let kclass = kk_kclass_create(typeToken, 0)
        XCTAssertEqual(kk_kclass_is_value(kclass), 1)
    }

    func testKClassIsInterfaceReturnsCorrectValue() {
        let typeToken = 204
        registerTestMetadata(typeToken: typeToken, flags: 1 << 3) // interface
        let kclass = kk_kclass_create(typeToken, 0)
        XCTAssertEqual(kk_kclass_is_interface(kclass), 1)
    }

    func testKClassIsObjectReturnsCorrectValue() {
        let typeToken = 205
        registerTestMetadata(typeToken: typeToken, flags: 1 << 4) // object
        let kclass = kk_kclass_create(typeToken, 0)
        XCTAssertEqual(kk_kclass_is_object(kclass), 1)
    }

    func testKClassIsEnumReturnsCorrectValue() {
        let typeToken = 206
        registerTestMetadata(typeToken: typeToken, flags: 1 << 5) // enumClass
        let kclass = kk_kclass_create(typeToken, 0)
        XCTAssertEqual(kk_kclass_is_enum(kclass), 1)
    }

    func testKClassIsAbstractReturnsCorrectValue() {
        let typeToken = 207
        registerTestMetadata(typeToken: typeToken, flags: 1 << 7) // abstract
        let kclass = kk_kclass_create(typeToken, 0)
        XCTAssertEqual(kk_kclass_is_abstract(kclass), 1)
    }

    func testKClassMembersCountReturnsCorrectValue() {
        let typeToken = 208
        let qualifiedName = makeRuntimeString("MemberTest")
        let simpleName = makeRuntimeString("MemberTest")
        let _ = kk_kclass_register_metadata(
            typeToken, qualifiedName, simpleName,
            0, 0, 3, 10, 1 // 3 fields, 10 members, 1 constructor
        )
        let kclass = kk_kclass_create(typeToken, 0)
        XCTAssertEqual(kk_kclass_members_count(kclass), 10)
    }

    func testKClassMembersCountReturnsMinusOneWhenNoMetadata() {
        let kclass = kk_kclass_create(9999, 0)
        XCTAssertEqual(kk_kclass_members_count(kclass), -1)
    }

    func testKClassSupertypeNameReturnsName() {
        let typeToken = 209
        let qualifiedName = makeRuntimeString("Child")
        let simpleName = makeRuntimeString("Child")
        let superName = makeRuntimeString("Parent")
        let _ = kk_kclass_register_metadata(
            typeToken, qualifiedName, simpleName,
            superName, 0, 0, 0, 0
        )
        let kclass = kk_kclass_create(typeToken, 0)
        let resultRaw = kk_kclass_supertype_name(kclass)
        let resultStr = extractString(from: UnsafeMutableRawPointer(bitPattern: resultRaw))
        XCTAssertEqual(resultStr, "Parent")
    }

    func testKClassSupertypeNameReturnsNullSentinelWhenNone() {
        let typeToken = 210
        let qualifiedName = makeRuntimeString("Root")
        let simpleName = makeRuntimeString("Root")
        let _ = kk_kclass_register_metadata(
            typeToken, qualifiedName, simpleName,
            0, 0, 0, 0, 0
        )
        let kclass = kk_kclass_create(typeToken, 0)
        let resultRaw = kk_kclass_supertype_name(kclass)
        XCTAssertEqual(resultRaw, runtimeNullSentinelInt)
    }

    // MARK: - Qualified Name With Metadata

    func testQualifiedNameUsesMetadataWhenAvailable() {
        let typeToken = 211
        let qualifiedName = makeRuntimeString("com.example.pkg.MyClass")
        let simpleName = makeRuntimeString("MyClass")
        let _ = kk_kclass_register_metadata(
            typeToken, qualifiedName, simpleName,
            0, 0, 0, 0, 0
        )
        let nameHint = makeRuntimeString("MyClass")
        let kclass = kk_kclass_create(typeToken, nameHint)
        let resultRaw = kk_kclass_qualified_name(kclass)
        let resultStr = extractString(from: UnsafeMutableRawPointer(bitPattern: resultRaw))
        XCTAssertEqual(resultStr, "com.example.pkg.MyClass")
    }

    // MARK: - Accessor Returns 0/False Without Metadata

    func testAccessorsReturnDefaultsWithoutMetadata() {
        let kclass = kk_kclass_create(8888, 0)
        XCTAssertEqual(kk_kclass_is_data(kclass), 0)
        XCTAssertEqual(kk_kclass_is_sealed(kclass), 0)
        XCTAssertEqual(kk_kclass_is_value(kclass), 0)
        XCTAssertEqual(kk_kclass_is_interface(kclass), 0)
        XCTAssertEqual(kk_kclass_is_object(kclass), 0)
        XCTAssertEqual(kk_kclass_is_enum(kclass), 0)
        XCTAssertEqual(kk_kclass_is_abstract(kclass), 0)
        XCTAssertEqual(kk_kclass_members_count(kclass), -1)
        XCTAssertEqual(kk_kclass_supertype_name(kclass), runtimeNullSentinelInt)
    }

    // MARK: - Multiple Flags

    func testMultipleFlagsCombined() {
        let typeToken = 300
        // sealed + abstract
        let flags = (1 << 1) | (1 << 7)
        registerTestMetadata(typeToken: typeToken, flags: flags)
        let kclass = kk_kclass_create(typeToken, 0)

        XCTAssertEqual(kk_kclass_is_data(kclass), 0)
        XCTAssertEqual(kk_kclass_is_sealed(kclass), 1)
        XCTAssertEqual(kk_kclass_is_value(kclass), 0)
        XCTAssertEqual(kk_kclass_is_abstract(kclass), 1)
    }

    // MARK: - Helpers

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
        }
    }

    private func registerTestMetadata(typeToken: Int, flags: Int) {
        let qualifiedName = makeRuntimeString("TestClass")
        let simpleName = makeRuntimeString("TestClass")
        let _ = kk_kclass_register_metadata(
            typeToken, qualifiedName, simpleName,
            0, flags, 0, 0, 0
        )
    }
}
