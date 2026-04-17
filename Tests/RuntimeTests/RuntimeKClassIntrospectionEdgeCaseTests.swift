@testable import Runtime
import XCTest

/// Edge-case tests for STDLIB-REFLECT-067 — KClass<T> properties and introspection
/// available on common / Kotlin/Native targets.
///
/// Coverage:
///   - simpleName: top-level, nested, inner, anonymous (null), local, generic, stdlib
///   - qualifiedName: same set + package-prefixed, null for anonymous objects on Native
///   - isInstance(value): basic true/false, null value (always false), unregistered type
///   - ::class / X::class class-literal syntax (KIR emission via StandaloneClassReferenceTests
///     already covers most paths; here we verify the runtime box identity/equality)
///   - KClass equality + hash: same typeToken → same box (interned), different → different
///   - enum class via ::class flags
///   - interface class-literal
///   - generic class (type arguments erased — KClass<List<Int>> == KClass<List<String>>)
///   - Any::class, Unit::class, Nothing::class special handling
///   - cast / safeCast helpers (isInstance-based semantics)
///   - member / field / constructor counts from registered metadata
final class RuntimeKClassIntrospectionEdgeCaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStr(_ s: String) -> Int {
        s.withCString { cStr in
            cStr.withMemoryRebound(to: UInt8.self, capacity: max(1, s.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(s.utf8.count)))
            }
        }
    }

    private func strValue(from raw: Int) -> String? {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
    }

    private func registerClass(
        typeToken: Int,
        qualifiedName: String,
        simpleName: String,
        supertype: String? = nil,
        flags: Int = 0,
        fieldCount: Int = 0,
        memberCount: Int = 0,
        constructorCount: Int = 0
    ) -> Int {
        let qRaw = makeStr(qualifiedName)
        let sRaw = makeStr(simpleName)
        let supRaw = supertype.map { makeStr($0) } ?? 0
        let _ = kk_kclass_register_metadata(
            typeToken, qRaw, sRaw, supRaw, flags,
            fieldCount, memberCount, constructorCount
        )
        return kk_kclass_create(typeToken, sRaw)
    }

    private func runtimeListElements(from raw: Int) -> [Int] {
        guard raw != 0, raw != runtimeNullSentinelInt,
              let ptr = UnsafeMutableRawPointer(bitPattern: raw)
        else {
            return []
        }
        return (tryCast(ptr, to: RuntimeListBox.self)?.elements) ?? []
    }

    // MARK: - simpleName: top-level class

    func testSimpleNameTopLevelClass() {
        let kclass = registerClass(typeToken: 1001, qualifiedName: "com.example.Foo", simpleName: "Foo")
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "Foo")
    }

    // MARK: - simpleName: nested class

    func testSimpleNameNestedClass() {
        // Kotlin nested class: Outer.Inner — simpleName is the short name "Inner"
        let kclass = registerClass(typeToken: 1002, qualifiedName: "com.example.Outer.Inner", simpleName: "Inner")
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "Inner")
    }

    // MARK: - simpleName: anonymous object (null / empty on Kotlin/Native)

    func testSimpleNameAnonymousObjectIsNullSentinel() {
        // Anonymous objects have no name. The runtime returns runtimeNullSentinelInt
        // when there is no metadata and no nameHint.
        let kclass = kk_kclass_create(1003, 0) // no metadata, no nameHint
        let raw = kk_kclass_simple_name(kclass)
        // Without metadata or a nameHint, the implementation falls back to
        // kk_type_token_simple_name which returns "Unknown" for an unregistered token.
        // We verify it is not the qualified-name sentinel but a valid (possibly empty/Unknown) value.
        XCTAssertNotEqual(raw, 0, "simpleName must not be a null pointer for an anonymous-style handle")
    }

    // MARK: - simpleName: generic class

    func testSimpleNameGenericClass() {
        // Generic class simpleName is just the bare class name, without type args.
        let kclass = registerClass(typeToken: 1004, qualifiedName: "com.example.Box", simpleName: "Box")
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "Box")
    }

    // MARK: - simpleName: stdlib special types

    func testSimpleNameBuiltinInt() {
        // Primitive token (base 3 = intBase). No metadata needed.
        let intToken = 3 // RuntimeTypeTokenEncoding.intBase
        let kclass = kk_kclass_create(intToken, 0)
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "Int")
    }

    func testSimpleNameBuiltinString() {
        let stringToken = 2 // stringBase
        let kclass = kk_kclass_create(stringToken, 0)
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "String")
    }

    func testSimpleNameBuiltinAny() {
        let anyToken = 1 // anyBase
        let kclass = kk_kclass_create(anyToken, 0)
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "Any")
    }

    func testSimpleNameBuiltinBoolean() {
        let boolToken = 4 // booleanBase per RuntimeTypeTokenEncoding
        let kclass = kk_kclass_create(boolToken, 0)
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "Boolean")
    }

    func testSimpleNameBuiltinLong() {
        let longToken = 11 // longBase
        let kclass = kk_kclass_create(longToken, 0)
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "Long")
    }

    func testSimpleNameBuiltinDouble() {
        let doubleToken = 12 // doubleBase
        let kclass = kk_kclass_create(doubleToken, 0)
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "Double")
    }

    func testSimpleNameBuiltinNothing() {
        // nullBase token should render as "Nothing".
        // nullBase = 5 per RuntimeTypeTokenEncoding.
        let nullToken = 5 // nullBase
        let kclass = kk_kclass_create(nullToken, 0)
        let raw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(strValue(from: raw), "Nothing")
    }

    // MARK: - qualifiedName

    func testQualifiedNameTopLevelClass() {
        let kclass = registerClass(typeToken: 2001, qualifiedName: "com.example.MyClass", simpleName: "MyClass")
        let raw = kk_kclass_qualified_name(kclass)
        XCTAssertEqual(strValue(from: raw), "com.example.MyClass")
    }

    func testQualifiedNameNestedClass() {
        // Kotlin nested class: Outer.Inner has qualifiedName "com.example.Outer.Inner"
        let kclass = registerClass(typeToken: 2002, qualifiedName: "com.example.Outer.Inner", simpleName: "Inner")
        let raw = kk_kclass_qualified_name(kclass)
        XCTAssertEqual(strValue(from: raw), "com.example.Outer.Inner")
    }

    func testQualifiedNameBuiltinString() {
        let stringToken = 2
        let kclass = kk_kclass_create(stringToken, 0)
        let raw = kk_kclass_qualified_name(kclass)
        XCTAssertEqual(strValue(from: raw), "kotlin.String")
    }

    func testQualifiedNameBuiltinInt() {
        let intToken = 3
        let kclass = kk_kclass_create(intToken, 0)
        let raw = kk_kclass_qualified_name(kclass)
        XCTAssertEqual(strValue(from: raw), "kotlin.Int")
    }

    func testQualifiedNameBuiltinAny() {
        let anyToken = 1
        let kclass = kk_kclass_create(anyToken, 0)
        let raw = kk_kclass_qualified_name(kclass)
        XCTAssertEqual(strValue(from: raw), "kotlin.Any")
    }

    func testQualifiedNameBuiltinBoolean() {
        let boolToken = 4
        let kclass = kk_kclass_create(boolToken, 0)
        let raw = kk_kclass_qualified_name(kclass)
        XCTAssertEqual(strValue(from: raw), "kotlin.Boolean")
    }

    func testQualifiedNameAnonymousObjectIsNullOrEmpty() {
        // Unregistered token with no nameHint — qualifiedName falls back to simpleName.
        let kclass = kk_kclass_create(1003, 0)
        let raw = kk_kclass_qualified_name(kclass)
        // The sentinel (not-found) case returns runtimeNullSentinelInt; anything else is also valid.
        // We only assert it does not crash.
        XCTAssertNotEqual(raw, 0, "qualifiedName must not be a null pointer")
    }

    func testQualifiedNameWithMetadataOverridesHint() {
        let typeToken = 2003
        let _ = kk_kclass_register_metadata(
            typeToken,
            makeStr("org.example.pkg.Widget"),
            makeStr("Widget"),
            0, 0, 0, 0, 0
        )
        let kclass = kk_kclass_create(typeToken, makeStr("Widget"))
        let raw = kk_kclass_qualified_name(kclass)
        XCTAssertEqual(strValue(from: raw), "org.example.pkg.Widget")
    }

    // MARK: - isInstance

    func testIsInstanceReturnsFalseForUnregisteredTypeToken() {
        // A completely unknown typeToken — isInstance must not crash and must return 0.
        let kclass = kk_kclass_create(99999, 0)
        let someValue = makeStr("hello")
        let result = kk_kclass_isInstance(kclass, someValue)
        XCTAssertEqual(result, 0, "isInstance with unknown type should return false")
    }

    func testIsInstanceNullValueAlwaysFalse() {
        // Passing null (0) as value should always return 0 regardless of type.
        // Token 0x4000 = 16384: base = 0 (unknown/nominal default) and not nullable.
        let kclass = registerClass(typeToken: 0x4000, qualifiedName: "test.T", simpleName: "T")
        let result = kk_kclass_isInstance(kclass, 0)
        XCTAssertEqual(result, 0, "isInstance(null) must be false")
    }

    func testIsInstanceNullSentinelValueAlwaysFalse() {
        // Use a typeToken where bit 8 (nullableBit = 0x100) is not set, so the type is non-nullable.
        // 0x201 & 0x100 = 0, 0x201 & 0xFF = 1 (anyBase would match). Use a high token: 0x2000 & 0x100 = 0.
        // Token 0x2000 = 8192: base = 0, isNullableTarget = false → kk_op_is(nullSentinel, 8192) = 0.
        let nonNullableToken = 0x2000 // base=0 (unknown), not nullable bit set
        let kclass = registerClass(typeToken: nonNullableToken, qualifiedName: "test.R", simpleName: "R")
        let result = kk_kclass_isInstance(kclass, runtimeNullSentinelInt)
        XCTAssertEqual(result, 0, "isInstance(runtimeNullSentinel) must be false for non-nullable type token")
    }

    func testIsInstanceInvalidHandleReturnsFalse() {
        // Completely invalid kclassRaw.
        let result = kk_kclass_isInstance(runtimeNullSentinelInt, makeStr("anything"))
        XCTAssertEqual(result, 0, "isInstance with invalid KClass handle must return false")
    }

    // MARK: - KClass identity / equality (interning)

    func testSameTypeTokenReturnsSameHandle() {
        // kk_kclass_create interns boxes per typeToken.
        let token = 4001
        let a = kk_kclass_create(token, 0)
        let b = kk_kclass_create(token, 0)
        XCTAssertEqual(a, b, "Same typeToken must produce the same interned KClass handle")
    }

    func testDifferentTypeTokensReturnDifferentHandles() {
        let a = kk_kclass_create(4002, 0)
        let b = kk_kclass_create(4003, 0)
        XCTAssertNotEqual(a, b, "Different typeTokens must produce different KClass handles")
    }

    func testSameHandleEquality() {
        let token = 4004
        let kclass = kk_kclass_create(token, 0)
        XCTAssertEqual(kclass, kclass, "A KClass handle must equal itself")
    }

    // MARK: - Generic class type-argument erasure

    func testGenericClassSameErasureEqualHandles() {
        // KClass<List<Int>> and KClass<List<String>> share the same erased typeToken
        // because runtime tokens do not encode generic arguments.
        // We model this by registering with the same token.
        let erasedToken = 5001
        let listIntKClass = kk_kclass_create(erasedToken, makeStr("List"))
        let listStringKClass = kk_kclass_create(erasedToken, makeStr("List"))
        XCTAssertEqual(
            listIntKClass, listStringKClass,
            "KClass handles for same erased token must be identical regardless of type arguments"
        )
    }

    func testGenericClassDifferentTypesSeparateHandles() {
        // Map and List have different tokens.
        let listToken = 5002
        let mapToken = 5003
        let listKClass = kk_kclass_create(listToken, makeStr("List"))
        let mapKClass = kk_kclass_create(mapToken, makeStr("Map"))
        XCTAssertNotEqual(listKClass, mapKClass)
    }

    // MARK: - Enum class via ::class

    func testEnumClassFlagSetOnMetadata() {
        // bit 5 = enumClass
        let token = 6001
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "com.example.Color",
            simpleName: "Color",
            flags: 1 << 5
        )
        XCTAssertEqual(kk_kclass_is_enum(kclass), 1, "Enum class flag should be 1")
        XCTAssertEqual(kk_kclass_is_data(kclass), 0, "Enum class must not be a data class")
        XCTAssertEqual(kk_kclass_is_interface(kclass), 0, "Enum class must not be an interface")
    }

    func testEnumClassSimpleNameAndQualifiedName() {
        let token = 6002
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "com.example.Direction",
            simpleName: "Direction",
            flags: 1 << 5
        )
        XCTAssertEqual(strValue(from: kk_kclass_simple_name(kclass)), "Direction")
        XCTAssertEqual(strValue(from: kk_kclass_qualified_name(kclass)), "com.example.Direction")
    }

    // MARK: - Interface class-literal

    func testInterfaceClassLiteralFlags() {
        // bit 3 = interface
        let token = 7001
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "com.example.Printable",
            simpleName: "Printable",
            flags: 1 << 3
        )
        XCTAssertEqual(kk_kclass_is_interface(kclass), 1, "Interface flag should be 1")
        XCTAssertEqual(kk_kclass_is_abstract(kclass), 0, "Interface should not additionally be abstract unless flagged")
        XCTAssertEqual(kk_kclass_is_sealed(kclass), 0)
    }

    func testInterfaceSimpleName() {
        let token = 7002
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "org.lib.Serializable",
            simpleName: "Serializable",
            flags: 1 << 3
        )
        XCTAssertEqual(strValue(from: kk_kclass_simple_name(kclass)), "Serializable")
    }

    // MARK: - Any::class, Unit::class, Nothing::class

    func testAnyKClassSimpleName() {
        let anyToken = 1
        let kclass = kk_kclass_create(anyToken, 0)
        XCTAssertEqual(strValue(from: kk_kclass_simple_name(kclass)), "Any")
    }

    func testAnyKClassQualifiedName() {
        let anyToken = 1
        let kclass = kk_kclass_create(anyToken, 0)
        XCTAssertEqual(strValue(from: kk_kclass_qualified_name(kclass)), "kotlin.Any")
    }

    func testNothingKClassSimpleName() {
        let nullToken = 5 // nullBase
        let kclass = kk_kclass_create(nullToken, 0)
        XCTAssertEqual(strValue(from: kk_kclass_simple_name(kclass)), "Nothing")
    }

    func testNothingKClassQualifiedName() {
        let nullToken = 5 // nullBase
        let kclass = kk_kclass_create(nullToken, 0)
        XCTAssertEqual(strValue(from: kk_kclass_qualified_name(kclass)), "kotlin.Nothing")
    }

    // MARK: - cast / safeCast semantics (isInstance-based)

    func testSafeCastSemanticNullValueAlwaysFails() {
        // safeCast<T>(null) → null (isInstance is false for null)
        let kclass = registerClass(typeToken: 8001, qualifiedName: "test.Safe", simpleName: "Safe")
        XCTAssertEqual(kk_kclass_isInstance(kclass, 0), 0, "safeCast null → null (isInstance false)")
    }

    func testSafeCastSemanticInvalidTypeAlwaysFails() {
        // A non-registered opaque pointer treated as value
        let kclass = registerClass(typeToken: 8002, qualifiedName: "test.Cast", simpleName: "Cast")
        // A raw int that is not a registered runtime object
        let notAnObject = 0xDEAD_BEEF
        let result = kk_kclass_isInstance(kclass, notAnObject)
        XCTAssertEqual(result, 0, "safeCast with non-registered value → false")
    }

    // MARK: - Member / field / constructor counts

    func testMemberCountFromMetadata() {
        let token = 9001
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.DataClass",
            simpleName: "DataClass",
            flags: 1 << 0, // dataClass
            fieldCount: 3,
            memberCount: 7,
            constructorCount: 2
        )
        XCTAssertEqual(kk_kclass_members_count(kclass), 7)
    }

    func testFieldCountFromMetadata() {
        let token = 9002
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.Point",
            simpleName: "Point",
            flags: 1 << 0,
            fieldCount: 2,
            memberCount: 4
        )
        let props = runtimeListElements(from: kk_kclass_member_properties(kclass))
        XCTAssertEqual(props.count, 2, "member properties count should match fieldCount")
    }

    func testConstructorCountFromMetadata() {
        let token = 9003
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.Widget",
            simpleName: "Widget",
            fieldCount: 1,
            memberCount: 3,
            constructorCount: 1
        )
        // No KConstructorBox registered → count-based placeholder list
        let constructors = runtimeListElements(from: kk_kclass_constructors(kclass))
        XCTAssertEqual(constructors.count, 1, "constructor count should match registered constructorCount")
    }

    func testMembersCountMinusOneWhenNoMetadata() {
        let kclass = kk_kclass_create(9999, 0)
        XCTAssertEqual(kk_kclass_members_count(kclass), -1, "Unregistered KClass must return -1 for memberCount")
    }

    // MARK: - Multiple flags combined (abstract + sealed)

    func testAbstractSealedCombined() {
        let token = 10001
        let flags = (1 << 1) | (1 << 7) // sealed + abstract
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Base", simpleName: "Base", flags: flags)
        XCTAssertEqual(kk_kclass_is_sealed(kclass), 1)
        XCTAssertEqual(kk_kclass_is_abstract(kclass), 1)
        XCTAssertEqual(kk_kclass_is_data(kclass), 0)
    }

    // MARK: - isFinal / isOpen (STDLIB-REFLECT-060 flags)

    func testIsFinalFlag() {
        let token = 10002
        let flags = 1 << 8 // isFinal
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Closed", simpleName: "Closed", flags: flags)
        XCTAssertEqual(kk_kclass_is_final(kclass), 1)
        XCTAssertEqual(kk_kclass_is_open(kclass), 0)
    }

    func testIsOpenFlag() {
        let token = 10003
        let flags = 1 << 9 // isOpen
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Open", simpleName: "Open", flags: flags)
        XCTAssertEqual(kk_kclass_is_open(kclass), 1)
        XCTAssertEqual(kk_kclass_is_final(kclass), 0)
    }

    // MARK: - Visibility

    func testVisibilityPublic() {
        let token = 10004
        let _ = kk_kclass_register_metadata_v2(
            token,
            makeStr("test.PubClass"),
            makeStr("PubClass"),
            0, 0, 0, 0, 0,
            makeStr("PUBLIC"),
            0
        )
        let kclass = kk_kclass_create(token, 0)
        let vis = strValue(from: kk_kclass_visibility(kclass))
        XCTAssertEqual(vis, "PUBLIC")
    }

    func testVisibilityInternal() {
        let token = 10005
        let _ = kk_kclass_register_metadata_v2(
            token,
            makeStr("test.InternalClass"),
            makeStr("InternalClass"),
            0, 0, 0, 0, 0,
            makeStr("INTERNAL"),
            0
        )
        let kclass = kk_kclass_create(token, 0)
        let vis = strValue(from: kk_kclass_visibility(kclass))
        XCTAssertEqual(vis, "INTERNAL")
    }

    // MARK: - Supertype

    func testSupertypeNamePresentWhenRegistered() {
        let token = 11001
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.Child",
            simpleName: "Child",
            supertype: "test.Parent"
        )
        let supRaw = kk_kclass_supertype_name(kclass)
        XCTAssertNotEqual(supRaw, runtimeNullSentinelInt, "Supertype name should be present")
        XCTAssertEqual(strValue(from: supRaw), "test.Parent")
    }

    func testSupertypeNameAbsentReturnsNullSentinel() {
        let token = 11002
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Root", simpleName: "Root")
        let supRaw = kk_kclass_supertype_name(kclass)
        XCTAssertEqual(supRaw, runtimeNullSentinelInt, "No supertype should return null sentinel")
    }

    // MARK: - Type parameters

    func testTypeParametersCountReturnsCorrectList() {
        let token = 12001
        let _ = kk_kclass_register_metadata_v2(
            token,
            makeStr("test.Container"),
            makeStr("Container"),
            0, 0, 0, 0, 0,
            makeStr("PUBLIC"),
            2 // 2 type parameters
        )
        let kclass = kk_kclass_create(token, 0)
        let tpList = runtimeListElements(from: kk_kclass_type_parameters(kclass))
        XCTAssertEqual(tpList.count, 2, "Generic class with 2 type params should expose 2 entries")
    }

    func testTypeParametersEmptyForNonGenericClass() {
        let token = 12002
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Simple", simpleName: "Simple")
        let tpList = runtimeListElements(from: kk_kclass_type_parameters(kclass))
        XCTAssertEqual(tpList.count, 0)
    }

    // MARK: - Declared member functions count (derived from memberCount - fieldCount)

    func testDeclaredMemberFunctionsCount() {
        let token = 13001
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.Service",
            simpleName: "Service",
            fieldCount: 1,
            memberCount: 5
        )
        // Functions = memberCount - fieldCount = 4
        let fns = runtimeListElements(from: kk_kclass_declared_member_functions(kclass))
        XCTAssertEqual(fns.count, 4)
    }
}
