import Foundation

typealias KKCustomDelegateGetterEntryPoint = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKCustomDelegateSetterEntryPoint = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

private let runtimeNotNullUninitializedMessage =
    "IllegalStateException: Property delegate must be assigned before being accessed."

@inline(__always)
private func runtimeTrapNotNullUninitialized() -> Never {
    // Top-level entry wrapper maps uncaught traps to KSWIFTK-LINK-0003 without forwarding
    // Swift's fatalError string; mirror the message on stderr so integration tests can assert it.
    FileHandle.standardError.write(Data((runtimeNotNullUninitializedMessage + "\n").utf8))
    fatalError(runtimeNotNullUninitializedMessage)
}

final class RuntimeCustomDelegateBox {
    let delegateHandle: Int
    let getValueFnPtr: Int
    let setValueFnPtr: Int

    init(delegateHandle: Int, getValueFnPtr: Int, setValueFnPtr: Int) {
        self.delegateHandle = delegateHandle
        self.getValueFnPtr = getValueFnPtr
        self.setValueFnPtr = setValueFnPtr
    }
}

// MARK: - KProperty Stub (PROP-007, STDLIB-REFLECT-062)

/// Minimal KProperty<*> stub carrying property name and return type.
/// Used as the `property` argument for `provideDelegate`, `getValue`, and `setValue`.
final class RuntimeKPropertyStub {
    let name: Int // intptr_t to a KKString (property name)
    let returnType: Int // intptr_t to a KKString (return type signature)
    // STDLIB-REFLECT-062: extended KProperty fields
    let visibility: Int // intptr_t to a KKString (e.g. "PUBLIC", "INTERNAL", etc.)
    let isLateinit: Bool
    let isConst: Bool
    /// Optional getter function pointer; 0 means not set.
    var getterFnPtr: Int
    /// Optional setter function pointer; 0 means not set.
    var setterFnPtr: Int
    /// The receiver object for get()/set() calls; 0 means top-level.
    var receiverPtr: Int

    init(
        name: Int,
        returnType: Int,
        visibility: Int = 0,
        isLateinit: Bool = false,
        isConst: Bool = false,
        getterFnPtr: Int = 0,
        setterFnPtr: Int = 0,
        receiverPtr: Int = 0
    ) {
        self.name = name
        self.returnType = returnType
        self.visibility = visibility
        self.isLateinit = isLateinit
        self.isConst = isConst
        self.getterFnPtr = getterFnPtr
        self.setterFnPtr = setterFnPtr
        self.receiverPtr = receiverPtr
    }
}

private func runtimeTagCallableRef(
    _ callable: Int,
    name: Int,
    arity: Int,
    kind: RuntimeCallableRefKind,
    isSuspend: Bool = false
) -> Int {
    runtimeStorage.withLock { state in
        state.callableRefMetadataByValue[callable] = RuntimeCallableRefMetadata(
            nameRaw: name,
            arity: arity,
            kind: kind,
            isSuspend: isSuspend
        )
    }
    return callable
}

@_cdecl("kk_callable_ref_tag_kfunction")
public func kk_callable_ref_tag_kfunction(_ callable: Int, _ name: Int, _ arity: Int, _ isSuspend: Int) -> Int {
    runtimeTagCallableRef(callable, name: name, arity: arity, kind: .function, isSuspend: isSuspend != 0)
}

@_cdecl("kk_callable_ref_tag_kproperty")
public func kk_callable_ref_tag_kproperty(_ callable: Int, _ name: Int, _ arity: Int) -> Int {
    runtimeTagCallableRef(callable, name: name, arity: arity, kind: .property, isSuspend: false)
}

@_cdecl("kk_callable_ref_name")
public func kk_callable_ref_name(_ tagged: Int) -> Int {
    runtimeStorage.withLock { state in
        state.callableRefMetadataByValue[tagged]?.nameRaw ?? runtimeNullSentinelInt
    }
}

// STDLIB-REFLECT-063: KFunction reflection helpers for callable refs.

@_cdecl("kk_callable_ref_arity")
public func kk_callable_ref_arity(_ tagged: Int) -> Int {
    runtimeStorage.withLock { state in
        state.callableRefMetadataByValue[tagged]?.arity ?? 0
    }
}

@_cdecl("kk_callable_ref_is_suspend")
public func kk_callable_ref_is_suspend(_ tagged: Int) -> Int {
    runtimeStorage.withLock { state in
        state.callableRefMetadataByValue[tagged]?.isSuspend == true ? 1 : 0
    }
}

@_cdecl("kk_callable_ref_parameters")
public func kk_callable_ref_parameters(_ tagged: Int) -> Int {
    let arity = runtimeStorage.withLock { state in
        state.callableRefMetadataByValue[tagged]?.arity ?? 0
    }
    // Return a runtime List of placeholder ints (one element per parameter).
    let placeholders = Array(repeating: 0, count: max(0, arity))
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}

/// Invokes a callable ref (tagged function pointer) with zero arguments (STDLIB-REFLECT-063).
/// For bound member references (closures), prepends the closure environment before calling.
@_cdecl("kk_callable_ref_call_0")
public func kk_callable_ref_call_0(
    _ tagged: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard tagged != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction call: null function reference")
        return 0
    }
    let expectedArity = runtimeStorage.withLock { state in
        state.callableRefMetadataByValue[tagged]?.arity
    }
    if let expectedArity {
        guard expectedArity == 0 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "KFunction call arity mismatch: expected \(expectedArity), got 0"
            )
            return 0
        }
    }
    if let box = runtimeFunctionValueBox(from: tagged) {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureThunkEntryPoint.self)
        return fn(box.closureRaw, outThrown)
    }
    let fn = unsafeBitCast(tagged, to: KKThunkEntryPoint.self)
    return fn(outThrown)
}

/// Invokes a callable ref (tagged function pointer) with one argument (STDLIB-REFLECT-063).
/// For bound member references (closures), prepends the closure environment before calling.
@_cdecl("kk_callable_ref_call_1")
public func kk_callable_ref_call_1(
    _ tagged: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard tagged != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction call: null function reference")
        return 0
    }
    let expectedArity = runtimeStorage.withLock { state in
        state.callableRefMetadataByValue[tagged]?.arity
    }
    if let expectedArity {
        guard expectedArity == 1 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "KFunction call arity mismatch: expected \(expectedArity), got 1"
            )
            return 0
        }
    }
    if let box = runtimeFunctionValueBox(from: tagged) {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint1.self)
        return fn(box.closureRaw, arg, outThrown)
    }
    let fn = unsafeBitCast(tagged, to: KKFunctionEntryPoint1.self)
    return fn(arg, outThrown)
}

/// Invokes a callable ref (tagged function pointer) with two arguments (STDLIB-REFLECT-063).
/// For bound member references (closures), prepends the closure environment before calling.
@_cdecl("kk_callable_ref_call_2")
public func kk_callable_ref_call_2(
    _ tagged: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard tagged != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction call: null function reference")
        return 0
    }
    let expectedArity = runtimeStorage.withLock { state in
        state.callableRefMetadataByValue[tagged]?.arity
    }
    if let expectedArity {
        guard expectedArity == 2 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "KFunction call arity mismatch: expected \(expectedArity), got 2"
            )
            return 0
        }
    }
    if let box = runtimeFunctionValueBox(from: tagged) {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        return fn(box.closureRaw, arg1, arg2, outThrown)
    }
    let fn = unsafeBitCast(tagged, to: KKFunctionEntryPoint2.self)
    return fn(arg1, arg2, outThrown)
}

/// Invokes a callable ref (tagged function pointer) with three arguments (STDLIB-REFLECT-063).
/// For bound member references (closures), prepends the closure environment before calling.
@_cdecl("kk_callable_ref_call_3")
public func kk_callable_ref_call_3(
    _ tagged: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard tagged != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "KFunction call: null function reference")
        return 0
    }
    let expectedArity = runtimeStorage.withLock { state in
        state.callableRefMetadataByValue[tagged]?.arity
    }
    if let expectedArity {
        guard expectedArity == 3 else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "KFunction call arity mismatch: expected \(expectedArity), got 3"
            )
            return 0
        }
    }
    if let box = runtimeFunctionValueBox(from: tagged) {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint3.self)
        return fn(box.closureRaw, arg1, arg2, arg3, outThrown)
    }
    let fn = unsafeBitCast(tagged, to: KKFunctionEntryPoint3.self)
    return fn(arg1, arg2, arg3, outThrown)
}

@_cdecl("kk_kproperty_stub_create")
public func kk_kproperty_stub_create(_ nameStr: Int, _ returnTypeStr: Int) -> Int {
    let stub = RuntimeKPropertyStub(name: nameStr, returnType: returnTypeStr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(stub).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

// STDLIB-REFLECT-062: extended create with full KProperty metadata
@_cdecl("kk_kproperty_stub_create_full")
public func kk_kproperty_stub_create_full(
    _ nameStr: Int,
    _ returnTypeStr: Int,
    _ visibilityStr: Int,
    _ isLateinit: Int,
    _ isConst: Int
) -> Int {
    let stub = RuntimeKPropertyStub(
        name: nameStr,
        returnType: returnTypeStr,
        visibility: visibilityStr,
        isLateinit: isLateinit != 0,
        isConst: isConst != 0
    )
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(stub).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_kproperty_stub_name")
public func kk_kproperty_stub_name(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KProperty handle in kk_kproperty_stub_name")
    }
    return stub.name
}

@_cdecl("kk_kproperty_stub_return_type")
public func kk_kproperty_stub_return_type(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KProperty handle in kk_kproperty_stub_return_type")
    }
    return stub.returnType
}

// STDLIB-REFLECT-062: visibility accessor
@_cdecl("kk_kproperty_stub_visibility")
public func kk_kproperty_stub_visibility(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return runtimeNullSentinelInt
    }
    if stub.visibility == 0 {
        if defaultKPropertyVisibilityPublicString == 0 {
            defaultKPropertyVisibilityPublicString = kk_kproperty_stub_make_string("PUBLIC")
        }
        return defaultKPropertyVisibilityPublicString
    }
    return stub.visibility
}

// STDLIB-REFLECT-062: isLateinit accessor
@_cdecl("kk_kproperty_stub_is_lateinit")
public func kk_kproperty_stub_is_lateinit(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return 0
    }
    return stub.isLateinit ? 1 : 0
}

// STDLIB-REFLECT-062: isConst accessor
@_cdecl("kk_kproperty_stub_is_const")
public func kk_kproperty_stub_is_const(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return 0
    }
    return stub.isConst ? 1 : 0
}

// STDLIB-REFLECT-062: attach getter function pointer to a KProperty stub
@_cdecl("kk_kproperty_stub_set_getter")
public func kk_kproperty_stub_set_getter(_ handle: Int, _ fnPtr: Int, _ receiver: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return 0
    }
    stub.getterFnPtr = fnPtr
    stub.receiverPtr = receiver
    return handle
}

// STDLIB-REFLECT-062: attach setter function pointer to a KProperty stub
@_cdecl("kk_kproperty_stub_set_setter")
public func kk_kproperty_stub_set_setter(_ handle: Int, _ fnPtr: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return 0
    }
    stub.setterFnPtr = fnPtr
    return handle
}

// STDLIB-REFLECT-062: return stored getter function pointer
@_cdecl("kk_kproperty_stub_getter")
public func kk_kproperty_stub_getter(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return 0
    }
    return stub.getterFnPtr
}

// STDLIB-REFLECT-062: return stored setter function pointer
@_cdecl("kk_kproperty_stub_setter")
public func kk_kproperty_stub_setter(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return 0
    }
    return stub.setterFnPtr
}

// STDLIB-REFLECT-062: invoke the getter via stored function pointer
@_cdecl("kk_kproperty_stub_get_value")
public func kk_kproperty_stub_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self),
          stub.getterFnPtr != 0
    else {
        return runtimeNullSentinelInt
    }
    typealias GetterFn = @convention(c) (Int) -> Int
    let fn = unsafeBitCast(stub.getterFnPtr, to: GetterFn.self)
    return fn(stub.receiverPtr)
}

// STDLIB-REFLECT-062: invoke the setter via stored function pointer
@_cdecl("kk_kproperty_stub_set_value")
public func kk_kproperty_stub_set_value(_ handle: Int, _ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self),
          stub.setterFnPtr != 0
    else {
        return 0
    }
    typealias SetterFn = @convention(c) (Int, Int) -> Int
    let fn = unsafeBitCast(stub.setterFnPtr, to: SetterFn.self)
    return fn(stub.receiverPtr, value)
}

/// Cached KKString handle for the default "PUBLIC" visibility value.
/// Initialized lazily on first use to avoid allocating a new string on every call.
private nonisolated(unsafe) var defaultKPropertyVisibilityPublicString: Int = 0

/// Build a KKString from a Swift String literal (used for default enum-like values).
private func kk_kproperty_stub_make_string(_ s: String) -> Int {
    let utf8 = Array(s.utf8)
    guard !utf8.isEmpty else { return runtimeNullSentinelInt }
    return utf8.withUnsafeBufferPointer { buffer in
        Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
    }
}

// MARK: - Lazy Delegate (P5-80)

@_cdecl("kk_lazy_create")
public func kk_lazy_create(_ initFnPtr: Int, _ mode: Int) -> Int {
    let safetyMode = LazyThreadSafetyMode(rawValue: mode) ?? .synchronized
    let box = RuntimeLazyBox(initializerFnPtr: initFnPtr, mode: safetyMode)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_lazy_get_value")
public func kk_lazy_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeLazyBox.self) else {
        return 0
    }
    return box.getValue()
}

@_cdecl("kk_lazy_is_initialized")
public func kk_lazy_is_initialized(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeLazyBox.self) else {
        return 0
    }
    return box.isInitialized ? 1 : 0
}

// MARK: - Observable Delegate (P5-80)

@_cdecl("kk_observable_create")
public func kk_observable_create(_ initialValue: Int, _ callbackFnPtr: Int) -> Int {
    let box = RuntimeObservableBox(initialValue: initialValue, callbackFnPtr: callbackFnPtr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_observable_get_value")
public func kk_observable_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeObservableBox.self) else {
        return 0
    }
    return box.currentValue
}

/// Invokes the callback **after** the value is changed (matching `kotlinc` semantics).
@_cdecl("kk_observable_set_value")
public func kk_observable_set_value(_ handle: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeObservableBox.self) else {
        return 0
    }
    let oldValue = box.currentValue
    box.currentValue = newValue
    // Invoke callback: (property, oldValue, newValue) -> void
    // property arg is 0 (KProperty stub) to match Kotlin's 3-param lambda signature.
    if box.callbackFnPtr != 0 {
        let callback = unsafeBitCast(box.callbackFnPtr, to: KKDelegateObserverEntryPoint.self)
        var thrown = 0
        _ = callback(0, oldValue, newValue, &thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: observable callback threw")
        }
    }
    return newValue
}

// MARK: - Vetoable Delegate (P5-80)

@_cdecl("kk_vetoable_create")
public func kk_vetoable_create(_ initialValue: Int, _ callbackFnPtr: Int) -> Int {
    let box = RuntimeVetoableBox(initialValue: initialValue, callbackFnPtr: callbackFnPtr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_vetoable_get_value")
public func kk_vetoable_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeVetoableBox.self) else {
        return 0
    }
    return box.currentValue
}

/// Invokes the callback **before** the value is changed; non-zero -> accept, zero -> veto.
@_cdecl("kk_vetoable_set_value")
public func kk_vetoable_set_value(_ handle: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeVetoableBox.self) else {
        return 0
    }
    let oldValue = box.currentValue
    // Invoke callback: (property, oldValue, newValue) -> intptr_t (boolean)
    // property arg is 0 (KProperty stub) to match Kotlin's 3-param lambda signature.
    if box.callbackFnPtr != 0 {
        let callback = unsafeBitCast(box.callbackFnPtr, to: KKDelegateObserverEntryPoint.self)
        var thrown = 0
        let accepted = callback(0, oldValue, newValue, &thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: vetoable callback threw")
        }
        if accepted != 0 {
            box.currentValue = newValue
        }
    } else {
        box.currentValue = newValue
    }
    return box.currentValue
}

// MARK: - NotNull Delegate (STDLIB-340)

@_cdecl("kk_notNull_create")
public func kk_notNull_create() -> Int {
    let box = RuntimeNotNullBox()
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_notNull_get_value")
public func kk_notNull_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        runtimeTrapNotNullUninitialized()
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeNotNullBox.self) else {
        runtimeTrapNotNullUninitialized()
    }
    guard let value = box.currentValue else {
        runtimeTrapNotNullUninitialized()
    }
    return value
}

@_cdecl("kk_notNull_set_value")
public func kk_notNull_set_value(_ handle: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        runtimeTrapNotNullUninitialized()
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeNotNullBox.self) else {
        runtimeTrapNotNullUninitialized()
    }
    box.currentValue = newValue
    return newValue
}

// MARK: - Custom Delegate

@_cdecl("kk_custom_delegate_create")
public func kk_custom_delegate_create(
    _ delegateHandle: Int,
    _ getValueFnPtr: Int,
    _ setValueFnPtr: Int
) -> Int {
    let box = RuntimeCustomDelegateBox(
        delegateHandle: delegateHandle,
        getValueFnPtr: getValueFnPtr,
        setValueFnPtr: setValueFnPtr
    )
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
        state.customDelegateBoxes[UInt(bitPattern: opaque)] = box
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_custom_delegate_get_value")
public func kk_custom_delegate_get_value(_ handle: Int, _ thisRef: Int, _ property: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let key = UInt(bitPattern: ptr)
    let box = runtimeStorage.withLock { state in
        state.customDelegateBoxes[key]
    }
    guard let box, box.getValueFnPtr != 0 else {
        return 0
    }
    let getter = unsafeBitCast(box.getValueFnPtr, to: KKCustomDelegateGetterEntryPoint.self)
    var thrown = 0
    let value = getter(box.delegateHandle, thisRef, property, &thrown)
    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: custom delegate getter threw")
    }
    return value
}

@_cdecl("kk_custom_delegate_set_value")
public func kk_custom_delegate_set_value(_ handle: Int, _ thisRef: Int, _ property: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return newValue
    }
    let key = UInt(bitPattern: ptr)
    let box = runtimeStorage.withLock { state in
        state.customDelegateBoxes[key]
    }
    guard let box else {
        return newValue
    }
    if box.setValueFnPtr == 0 {
        return newValue
    }
    let setter = unsafeBitCast(box.setValueFnPtr, to: KKCustomDelegateSetterEntryPoint.self)
    var thrown = 0
    let result = setter(box.delegateHandle, thisRef, property, newValue, &thrown)
    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: custom delegate setter threw")
    }
    return result
}

// MARK: - Generic Delegate Operator Shims

/// Bridges compiler-emitted delegated property accessors that still lower to
/// `getValue` / `setValue` symbols instead of direct runtime helper names.
@_cdecl("kk_delegate_get_value")
public func kk_delegate_get_value(_ handle: Int, _: Int, _ property: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj else {
        return 0
    }
    if let lazyBox = tryCast(ptr, to: RuntimeLazyBox.self) {
        return lazyBox.getValue()
    }
    if let observableBox = tryCast(ptr, to: RuntimeObservableBox.self) {
        return observableBox.currentValue
    }
    if let vetoableBox = tryCast(ptr, to: RuntimeVetoableBox.self) {
        return vetoableBox.currentValue
    }
    if let notNullBox = tryCast(ptr, to: RuntimeNotNullBox.self) {
        guard let value = notNullBox.currentValue else {
            runtimeTrapNotNullUninitialized()
        }
        return value
    }
    // Map-backed property delegation (STDLIB-335)
    if let mapBox = tryCast(ptr, to: RuntimeMapBox.self) {
        let propName = kk_kproperty_stub_name(property)
        for i in 0..<mapBox.keys.count {
            if kk_string_equals(mapBox.keys[i], propName) != 0 {
                return mapBox.values[i]
            }
        }
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: key not found in map delegate")
    }
    return 0
}

/// Bridges compiler-emitted delegated property setters that still lower to
/// `setValue` instead of direct runtime helper names.
@_cdecl("kk_delegate_set_value")
public func kk_delegate_set_value(_ handle: Int, _: Int, _ property: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj else {
        return 0
    }
    if let observableBox = tryCast(ptr, to: RuntimeObservableBox.self) {
        let oldValue = observableBox.currentValue
        observableBox.currentValue = newValue
        if observableBox.callbackFnPtr != 0 {
            let callback = unsafeBitCast(observableBox.callbackFnPtr, to: KKDelegateObserverEntryPoint.self)
            var thrown = 0
            _ = callback(0, oldValue, newValue, &thrown)
            if thrown != 0 {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: observable callback threw")
            }
        }
        return newValue
    }
    if let vetoableBox = tryCast(ptr, to: RuntimeVetoableBox.self) {
        let oldValue = vetoableBox.currentValue
        if vetoableBox.callbackFnPtr != 0 {
            let callback = unsafeBitCast(vetoableBox.callbackFnPtr, to: KKDelegateObserverEntryPoint.self)
            var thrown = 0
            let accepted = callback(0, oldValue, newValue, &thrown)
            if thrown != 0 {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: vetoable callback threw")
            }
            if accepted != 0 {
                vetoableBox.currentValue = newValue
            }
        } else {
            vetoableBox.currentValue = newValue
        }
        return vetoableBox.currentValue
    }
    if let notNullBox = tryCast(ptr, to: RuntimeNotNullBox.self) {
        notNullBox.currentValue = newValue
        return newValue
    }
    // MutableMap-backed property delegation (STDLIB-335)
    if let mapBox = tryCast(ptr, to: RuntimeMapBox.self) {
        let propName = kk_kproperty_stub_name(property)
        for i in 0..<mapBox.keys.count {
            if kk_string_equals(mapBox.keys[i], propName) != 0 {
                mapBox.values[i] = newValue
                return newValue
            }
        }
        // Key not present yet — insert new entry.
        mapBox.keys.append(propName)
        mapBox.values.append(newValue)
        return newValue
    }
    return newValue
}
