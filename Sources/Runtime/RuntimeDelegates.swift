import Foundation

typealias KKCustomDelegateGetterEntryPoint = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKCustomDelegateSetterEntryPoint = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

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

@_cdecl("kk_kproperty_stub_create")
public func kk_kproperty_stub_create(_ nameStr: Int, _ returnTypeStr: Int) -> Int {
    let stub = RuntimeKPropertyStub(name: nameStr, returnType: returnTypeStr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(stub).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

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

/// Invokes the callback **before** the value is changed; non-zero → accept, zero → veto.
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
        fatalError("IllegalStateException: Property delegate must be assigned before being accessed.")
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeNotNullBox.self) else {
        fatalError("IllegalStateException: Property delegate must be assigned before being accessed.")
    }
    guard let value = box.currentValue else {
        fatalError("IllegalStateException: Property delegate must be assigned before being accessed.")
    }
    return value
}

@_cdecl("kk_notNull_set_value")
public func kk_notNull_set_value(_ handle: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return newValue
    }
    let isObj = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeNotNullBox.self) else {
        return newValue
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
public func kk_delegate_get_value(_ handle: Int, _: Int, _: Int) -> Int {
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
            fatalError("IllegalStateException: Property delegate must be assigned before being accessed.")
        }
        return value
    }
    return 0
}

/// Bridges compiler-emitted delegated property setters that still lower to
/// `setValue` instead of direct runtime helper names.
@_cdecl("kk_delegate_set_value")
public func kk_delegate_set_value(_ handle: Int, _: Int, _: Int, _ newValue: Int) -> Int {
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
    return newValue
}
