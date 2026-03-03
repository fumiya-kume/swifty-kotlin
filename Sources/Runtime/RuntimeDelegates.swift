import Foundation

// MARK: - KProperty Stub (PROP-007)

/// Minimal KProperty<*> stub carrying property name and return type.
/// Used as the `property` argument for `provideDelegate`, `getValue`, and `setValue`.
final class RuntimeKPropertyStub {
    let name: Int // intptr_t to a KKString (property name)
    let returnType: Int // intptr_t to a KKString (return type signature)

    init(name: Int, returnType: Int) {
        self.name = name
        self.returnType = returnType
    }
}

/// Creates a minimal KProperty<*> stub with name and returnType strings.
/// - Parameters:
///   - nameStr: intptr_t pointing to the property name KKString.
///   - returnTypeStr: intptr_t pointing to the return type signature KKString.
/// - Returns: Opaque handle (Int) to the `RuntimeKPropertyStub`.
@_cdecl("kk_kproperty_stub_create")
public func kk_kproperty_stub_create(_ nameStr: Int, _ returnTypeStr: Int) -> Int {
    let stub = RuntimeKPropertyStub(name: nameStr, returnType: returnTypeStr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(stub).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Returns the name field of a KProperty stub.
/// - Parameter handle: Opaque handle returned by `kk_kproperty_stub_create`.
/// - Returns: The property name intptr_t (KKString pointer), or 0 if invalid.
@_cdecl("kk_kproperty_stub_name")
public func kk_kproperty_stub_name(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let stub = tryCast(ptr, to: RuntimeKPropertyStub.self) else {
        return 0
    }
    return stub.name
}

/// Returns the returnType field of a KProperty stub.
/// - Parameter handle: Opaque handle returned by `kk_kproperty_stub_create`.
/// - Returns: The return type intptr_t (KKString pointer), or 0 if invalid.
@_cdecl("kk_kproperty_stub_return_type")
public func kk_kproperty_stub_return_type(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let stub = tryCast(ptr, to: RuntimeKPropertyStub.self) else {
        return 0
    }
    return stub.returnType
}

// MARK: - Lazy Delegate (P5-80)

/// Creates a new lazy delegate instance.
/// - Parameters:
///   - initFnPtr: Function pointer to the initializer lambda (`() -> T`).
///   - mode: Thread-safety mode (1 = SYNCHRONIZED, 0 = NONE).
/// - Returns: Opaque handle (Int) to the `RuntimeLazyBox`.
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

/// Returns the lazily-initialized value. Initializes on first access.
/// - Parameter handle: Opaque handle returned by `kk_lazy_create`.
/// - Returns: The cached or freshly computed value.
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

/// Returns whether the lazy delegate has been initialized.
/// - Parameter handle: Opaque handle returned by `kk_lazy_create`.
/// - Returns: 1 if initialized, 0 otherwise.
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

/// Creates an observable delegate instance.
/// - Parameters:
///   - initialValue: The initial property value.
///   - callbackFnPtr: Function pointer to the observer callback
///     `(property: intptr_t, oldValue: intptr_t, newValue: intptr_t) -> void`.
/// - Returns: Opaque handle to the `RuntimeObservableBox`.
@_cdecl("kk_observable_create")
public func kk_observable_create(_ initialValue: Int, _ callbackFnPtr: Int) -> Int {
    let box = RuntimeObservableBox(initialValue: initialValue, callbackFnPtr: callbackFnPtr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Returns the current value of an observable delegate.
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

/// Sets the value of an observable delegate.
/// Invokes the callback **after** the value is changed (matching `kotlinc` semantics).
/// Callback signature: `(property: intptr_t, oldValue: intptr_t, newValue: intptr_t) -> void`
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
        let callback = unsafeBitCast(box.callbackFnPtr, to: (@convention(c) (Int, Int, Int) -> Void).self)
        callback(0, oldValue, newValue)
    }
    return newValue
}

// MARK: - Vetoable Delegate (P5-80)

/// Creates a vetoable delegate instance.
/// - Parameters:
///   - initialValue: The initial property value.
///   - callbackFnPtr: Function pointer to the veto callback
///     `(property: intptr_t, oldValue: intptr_t, newValue: intptr_t) -> intptr_t`.
///     Returns non-zero to accept the change, zero to veto.
/// - Returns: Opaque handle to the `RuntimeVetoableBox`.
@_cdecl("kk_vetoable_create")
public func kk_vetoable_create(_ initialValue: Int, _ callbackFnPtr: Int) -> Int {
    let box = RuntimeVetoableBox(initialValue: initialValue, callbackFnPtr: callbackFnPtr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Returns the current value of a vetoable delegate.
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

/// Sets the value of a vetoable delegate.
/// Invokes the callback **before** the value is changed (matching `kotlinc` semantics).
/// Callback signature: `(property: intptr_t, oldValue: intptr_t, newValue: intptr_t) -> intptr_t`
/// Returns non-zero → accept; zero → veto (value unchanged).
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
        let callback = unsafeBitCast(box.callbackFnPtr, to: (@convention(c) (Int, Int, Int) -> Int).self)
        let accepted = callback(0, oldValue, newValue)
        if accepted != 0 {
            box.currentValue = newValue
        }
    } else {
        box.currentValue = newValue
    }
    return box.currentValue
}
