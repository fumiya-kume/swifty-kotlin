func runtimeListBox(from rawValue: Int) -> RuntimeListBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeListBox.self)
}

func runtimeMapBox(from rawValue: Int) -> RuntimeMapBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeMapBox.self)
}

func runtimeListIteratorBox(from rawValue: Int) -> RuntimeListIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeListIteratorBox.self)
}

func runtimeMapIteratorBox(from rawValue: Int) -> RuntimeMapIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeMapIteratorBox.self)
}

func runtimeMapArrayPair(
    keysRaw: Int,
    valuesRaw: Int
) -> (keys: [Int], values: [Int])? {
    guard let keysArray = runtimeArrayBox(from: keysRaw),
          let valuesArray = runtimeArrayBox(from: valuesRaw)
    else {
        return nil
    }
    return (keysArray.elements, valuesArray.elements)
}

func registerRuntimeObject(_ box: AnyObject) -> Int {
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

func maybeUnbox(_ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
        return value
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return value
    }
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let boolBox = tryCast(ptr, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    if let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
        return longBox.value
    }
    if let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
        return charBox.value
    }
    return value
}

func runtimeElementToString(_ elem: Int) -> String {
    if elem == runtimeNullSentinelInt {
        return "null"
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: elem) else {
        return "\(elem)"
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return "\(elem)"
    }
    if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
        return stringBox.value
    }
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
        return "\(intBox.value)"
    }
    if let boolBox = tryCast(ptr, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
        return "\(longBox.value)"
    }
    if let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
        return String(floatBox.value)
    }
    if let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
        return String(doubleBox.value)
    }
    if let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
        return UnicodeScalar(charBox.value).map(String.init) ?? "\u{FFFD}"
    }
    if let listBox = tryCast(ptr, to: RuntimeListBox.self) {
        let parts = listBox.elements.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let mapBox = tryCast(ptr, to: RuntimeMapBox.self) {
        let parts = zip(mapBox.keys, mapBox.values).map { key, value in
            "\(runtimeElementToString(key))=\(runtimeElementToString(value))"
        }
        return "{" + parts.joined(separator: ", ") + "}"
    }
    return "\(elem)"
}
