import Foundation

// Stable nominal IDs for runtime-backed kotlin.reflect values.
//
// The compiler's nominal type tokens use the same FNV-1a-derived IDs. Keeping
// the IDs in one runtime-owned table lets reflection handles participate in
// `is`/`as` checks without depending on allocation order.
let kCallableRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KCallable")
let kFunctionRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction")
let kConstructorRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KConstructor")
let kPropertyRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KProperty")
let kMutablePropertyRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KMutableProperty")
let kProperty0RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KProperty0")
let kProperty1RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KProperty1")
let kProperty2RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KProperty2")
let kMutableProperty0RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KMutableProperty0")
let kMutableProperty1RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KMutableProperty1")
let kMutableProperty2RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KMutableProperty2")
let kFunction0RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction0")
let kFunction1RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction1")
let kFunction2RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction2")
let kFunction3RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction3")
let kClassifierRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KClassifier")
let kClassRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KClass")
let kTypeRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KType")
let kTypeParameterRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KTypeParameter")
let kTypeProjectionRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KTypeProjection")
let kParameterRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KParameter")

private let reflectionRuntimeTypeMetadataEdges: [(Int64, Int64)] = [
    (kFunctionRuntimeTypeID, kCallableRuntimeTypeID),
    (kConstructorRuntimeTypeID, kFunctionRuntimeTypeID),
    (kPropertyRuntimeTypeID, kCallableRuntimeTypeID),
    (kMutablePropertyRuntimeTypeID, kPropertyRuntimeTypeID),
    (kProperty0RuntimeTypeID, kPropertyRuntimeTypeID),
    (kProperty1RuntimeTypeID, kPropertyRuntimeTypeID),
    (kProperty2RuntimeTypeID, kPropertyRuntimeTypeID),
    (kMutableProperty0RuntimeTypeID, kMutablePropertyRuntimeTypeID),
    (kMutableProperty0RuntimeTypeID, kProperty0RuntimeTypeID),
    (kMutableProperty1RuntimeTypeID, kMutablePropertyRuntimeTypeID),
    (kMutableProperty1RuntimeTypeID, kProperty1RuntimeTypeID),
    (kMutableProperty2RuntimeTypeID, kMutablePropertyRuntimeTypeID),
    (kMutableProperty2RuntimeTypeID, kProperty2RuntimeTypeID),
    (kFunction0RuntimeTypeID, kFunctionRuntimeTypeID),
    (kFunction1RuntimeTypeID, kFunctionRuntimeTypeID),
    (kFunction2RuntimeTypeID, kFunctionRuntimeTypeID),
    (kFunction3RuntimeTypeID, kFunctionRuntimeTypeID),
    (kClassRuntimeTypeID, kClassifierRuntimeTypeID),
    (kTypeRuntimeTypeID, kClassifierRuntimeTypeID),
    (kTypeParameterRuntimeTypeID, kClassifierRuntimeTypeID),
]

private let reflectionRuntimeTypeMetadataRegistration: Void = {
    for (childTypeID, parentTypeID) in reflectionRuntimeTypeMetadataEdges {
        runtimeRegisterTypeEdge(childTypeID: childTypeID, parentTypeID: parentTypeID)
    }
}()

/// Registers the reflection hierarchy before a handle is tagged.
@inline(__always)
func registerReflectionRuntimeTypeMetadata() {
    _ = reflectionRuntimeTypeMetadataRegistration
    // Runtime test isolation clears type edges; Set insertion makes this safe
    // and keeps newly created handles castable after a metadata reset.
    for (childTypeID, parentTypeID) in reflectionRuntimeTypeMetadataEdges {
        runtimeRegisterTypeEdge(childTypeID: childTypeID, parentTypeID: parentTypeID)
    }
}

/// Returns a live runtime reflection box of the requested Swift type.
func runtimeReflectionObject<T: AnyObject>(from raw: Int, as type: T.Type) -> T? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: type)
}

/// Shared KCallable.name dispatch for every runtime reflection box returned by
/// KClass member and constructor queries.
@_cdecl("__kk_kcallable_get_name")
public func __kk_kcallable_get_name(_ callableRaw: Int) -> Int {
    if let taggedName = runtimeStorage.withDelegateLock({ state in
        state.callableRefMetadataByValue[callableRaw]?.nameRaw
    }) {
        return taggedName
    }
    if let function = runtimeReflectionObject(from: callableRaw, as: RuntimeKFunctionBox.self) {
        return function.nameRaw
    }
    if let constructor = runtimeReflectionObject(from: callableRaw, as: RuntimeKConstructorBox.self) {
        return constructor.nameRaw
    }
    if let property = runtimeReflectionObject(from: callableRaw, as: RuntimeKPropertyStub.self) {
        return property.name
    }
    return runtimeNullSentinelInt
}

/// Shared KCallable.returnType dispatch for runtime reflection boxes and
/// compiler-tagged callable references.
@_cdecl("__kk_kcallable_get_return_type")
public func __kk_kcallable_get_return_type(_ callableRaw: Int) -> Int {
    let returnTypeRaw: Int?
    if let taggedReturnType = runtimeStorage.withDelegateLock({ state in
        state.callableRefMetadataByValue[callableRaw]?.returnTypeRaw
    }) {
        returnTypeRaw = taggedReturnType
    } else if let function = runtimeReflectionObject(from: callableRaw, as: RuntimeKFunctionBox.self) {
        returnTypeRaw = function.returnTypeRaw
    } else if let constructor = runtimeReflectionObject(from: callableRaw, as: RuntimeKConstructorBox.self) {
        returnTypeRaw = constructor.returnTypeRaw
    } else if let property = runtimeReflectionObject(from: callableRaw, as: RuntimeKPropertyStub.self) {
        returnTypeRaw = property.returnType
    } else {
        returnTypeRaw = nil
    }

    guard let returnTypeRaw,
          returnTypeRaw != 0,
          returnTypeRaw != runtimeNullSentinelInt,
          extractString(from: UnsafeMutableRawPointer(bitPattern: returnTypeRaw)) != nil
    else {
        return runtimeNullSentinelInt
    }

    // The metadata fields predate RuntimeKTypeBox and store a KKString
    // descriptor. Box that descriptor at the KCallable boundary so the
    // source-level return type is an actual KType value.
    let typeName = extractString(from: UnsafeMutableRawPointer(bitPattern: returnTypeRaw)) ?? ""
    let box = RuntimeKTypeBox(
        classifierRaw: __kk_kclass_create(0, returnTypeRaw),
        argumentRaws: [],
        isMarkedNullable: typeName.hasSuffix("?"),
        typeNameRaw: returnTypeRaw
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kTypeRuntimeTypeID)
}
