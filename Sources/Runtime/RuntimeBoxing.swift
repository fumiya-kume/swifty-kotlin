import Foundation

@_cdecl("kk_box_int")
public func kk_box_int(_ value: Int) -> Int {
    if value == runtimeNullSentinelInt { return value }
    let box = RuntimeIntBox(value)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: opaque)
}

@_cdecl("kk_box_bool")
public func kk_box_bool(_ value: Int) -> Int {
    if value == runtimeNullSentinelInt { return value }
    let box = RuntimeBoolBox(value != 0)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return Int(bitPattern: opaque)
}

@_cdecl("kk_unbox_int")
public func kk_unbox_int(_ obj: Int) -> Int {
    if obj == runtimeNullSentinelInt {
        return 0
    }
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else {
        return obj
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: objPointer))
    RuntimeStorage.lock.unlock()
    guard isObjectPointer else {
        return obj
    }
    if let intBox = tryCast(objPointer, to: RuntimeIntBox.self) {
        return intBox.value
    }
    return obj
}

@_cdecl("kk_unbox_bool")
public func kk_unbox_bool(_ obj: Int) -> Int {
    if obj == runtimeNullSentinelInt {
        return 0
    }
    guard let objPointer = UnsafeMutableRawPointer(bitPattern: obj) else {
        return obj != 0 ? 1 : 0
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: objPointer))
    RuntimeStorage.lock.unlock()
    guard isObjectPointer else {
        return obj != 0 ? 1 : 0
    }
    if let boolBox = tryCast(objPointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    return obj != 0 ? 1 : 0
}
