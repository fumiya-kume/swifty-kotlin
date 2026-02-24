import Foundation

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
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
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
    RuntimeStorage.lock.lock()
    let isObj = RuntimeStorage.objectPointers.contains(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    guard isObj, let box = tryCast(ptr, to: RuntimeLazyBox.self) else {
        return 0
    }
    return box.getValue()
}

// MARK: - Observable Delegate (P5-80)

/// Creates an observable delegate instance.
/// - Parameters:
///   - initialValue: The initial property value.
///   - callbackFnPtr: Function pointer to the observer callback
///     `(oldValue: intptr_t, newValue: intptr_t) -> void`.
/// - Returns: Opaque handle to the `RuntimeObservableBox`.
@_cdecl("kk_observable_create")
public func kk_observable_create(_ initialValue: Int, _ callbackFnPtr: Int) -> Int {
    let box = RuntimeObservableBox(initialValue: initialValue, callbackFnPtr: callbackFnPtr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: opaque)
}

/// Returns the current value of an observable delegate.
@_cdecl("kk_observable_get_value")
public func kk_observable_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    RuntimeStorage.lock.lock()
    let isObj = RuntimeStorage.objectPointers.contains(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    guard isObj, let box = tryCast(ptr, to: RuntimeObservableBox.self) else {
        return 0
    }
    return box.currentValue
}

/// Sets the value of an observable delegate.
/// Invokes the callback **after** the value is changed (matching `kotlinc` semantics).
/// Callback signature: `(oldValue: intptr_t, newValue: intptr_t) -> void`
@_cdecl("kk_observable_set_value")
public func kk_observable_set_value(_ handle: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    RuntimeStorage.lock.lock()
    let isObj = RuntimeStorage.objectPointers.contains(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    guard isObj, let box = tryCast(ptr, to: RuntimeObservableBox.self) else {
        return 0
    }
    let oldValue = box.currentValue
    box.currentValue = newValue
    // Invoke callback: (oldValue, newValue) -> void
    if box.callbackFnPtr != 0 {
        let callback = unsafeBitCast(box.callbackFnPtr, to: (@convention(c) (Int, Int) -> Void).self)
        callback(oldValue, newValue)
    }
    return newValue
}

// MARK: - Vetoable Delegate (P5-80)

/// Creates a vetoable delegate instance.
/// - Parameters:
///   - initialValue: The initial property value.
///   - callbackFnPtr: Function pointer to the veto callback
///     `(oldValue: intptr_t, newValue: intptr_t) -> intptr_t`.
///     Returns non-zero to accept the change, zero to veto.
/// - Returns: Opaque handle to the `RuntimeVetoableBox`.
@_cdecl("kk_vetoable_create")
public func kk_vetoable_create(_ initialValue: Int, _ callbackFnPtr: Int) -> Int {
    let box = RuntimeVetoableBox(initialValue: initialValue, callbackFnPtr: callbackFnPtr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: opaque)
}

/// Returns the current value of a vetoable delegate.
@_cdecl("kk_vetoable_get_value")
public func kk_vetoable_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    RuntimeStorage.lock.lock()
    let isObj = RuntimeStorage.objectPointers.contains(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    guard isObj, let box = tryCast(ptr, to: RuntimeVetoableBox.self) else {
        return 0
    }
    return box.currentValue
}

/// Sets the value of a vetoable delegate.
/// Invokes the callback **before** the value is changed (matching `kotlinc` semantics).
/// Callback signature: `(oldValue: intptr_t, newValue: intptr_t) -> intptr_t`
/// Returns non-zero → accept; zero → veto (value unchanged).
@_cdecl("kk_vetoable_set_value")
public func kk_vetoable_set_value(_ handle: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    RuntimeStorage.lock.lock()
    let isObj = RuntimeStorage.objectPointers.contains(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    guard isObj, let box = tryCast(ptr, to: RuntimeVetoableBox.self) else {
        return 0
    }
    let oldValue = box.currentValue
    // Invoke callback: (oldValue, newValue) -> intptr_t (boolean)
    if box.callbackFnPtr != 0 {
        let callback = unsafeBitCast(box.callbackFnPtr, to: (@convention(c) (Int, Int) -> Int).self)
        let accepted = callback(oldValue, newValue)
        if accepted != 0 {
            box.currentValue = newValue
        }
    } else {
        box.currentValue = newValue
    }
    return box.currentValue
}
