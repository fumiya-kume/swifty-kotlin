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

func runtimeSetBox(from rawValue: Int) -> RuntimeSetBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeSetBox.self)
}

func runtimeArrayDequeBox(from rawValue: Int) -> RuntimeArrayDequeBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeArrayDequeBox.self)
}

func runtimeCollectionElements(from rawValue: Int) -> [Int]? {
    if let listBox = runtimeListBox(from: rawValue) {
        return listBox.elements
    }
    if let setBox = runtimeSetBox(from: rawValue) {
        return setBox.elements
    }
    return nil
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

func runtimeStringIteratorBox(from rawValue: Int) -> RuntimeStringIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeStringIteratorBox.self)
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

func runtimeValuesEqual(_ lhs: Int, _ rhs: Int) -> Bool {
    if lhs == rhs {
        return true
    }
    if lhs == runtimeNullSentinelInt || rhs == runtimeNullSentinelInt {
        return lhs == rhs
    }
    guard let lhsPtr = UnsafeMutableRawPointer(bitPattern: lhs),
          let rhsPtr = UnsafeMutableRawPointer(bitPattern: rhs)
    else {
        return lhs == rhs
    }
    let lhsIsObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: lhsPtr))
    }
    let rhsIsObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: rhsPtr))
    }
    if lhsIsObjectPointer != rhsIsObjectPointer {
        return maybeUnbox(lhs) == maybeUnbox(rhs)
    }
    if !lhsIsObjectPointer {
        return lhs == rhs
    }
    if let lhsString = tryCast(lhsPtr, to: RuntimeStringBox.self),
       let rhsString = tryCast(rhsPtr, to: RuntimeStringBox.self)
    {
        return lhsString.value == rhsString.value
    }
    if let lhsInt = tryCast(lhsPtr, to: RuntimeIntBox.self),
       let rhsInt = tryCast(rhsPtr, to: RuntimeIntBox.self)
    {
        return lhsInt.value == rhsInt.value
    }
    if let lhsBool = tryCast(lhsPtr, to: RuntimeBoolBox.self),
       let rhsBool = tryCast(rhsPtr, to: RuntimeBoolBox.self)
    {
        return lhsBool.value == rhsBool.value
    }
    if let lhsLong = tryCast(lhsPtr, to: RuntimeLongBox.self),
       let rhsLong = tryCast(rhsPtr, to: RuntimeLongBox.self)
    {
        return lhsLong.value == rhsLong.value
    }
    if let lhsFloat = tryCast(lhsPtr, to: RuntimeFloatBox.self),
       let rhsFloat = tryCast(rhsPtr, to: RuntimeFloatBox.self)
    {
        return lhsFloat.value == rhsFloat.value
    }
    if let lhsDouble = tryCast(lhsPtr, to: RuntimeDoubleBox.self),
       let rhsDouble = tryCast(rhsPtr, to: RuntimeDoubleBox.self)
    {
        return lhsDouble.value == rhsDouble.value
    }
    if let lhsChar = tryCast(lhsPtr, to: RuntimeCharBox.self),
       let rhsChar = tryCast(rhsPtr, to: RuntimeCharBox.self)
    {
        return lhsChar.value == rhsChar.value
    }
    return lhs == rhs
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
    if let setBox = tryCast(ptr, to: RuntimeSetBox.self) {
        let parts = setBox.elements.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let mapBox = tryCast(ptr, to: RuntimeMapBox.self) {
        let parts = zip(mapBox.keys, mapBox.values).map { key, value in
            "\(runtimeElementToString(key))=\(runtimeElementToString(value))"
        }
        return "{" + parts.joined(separator: ", ") + "}"
    }
    if let pairBox = tryCast(ptr, to: RuntimePairBox.self) {
        let first = runtimeElementToString(pairBox.first)
        let second = runtimeElementToString(pairBox.second)
        return "(\(first), \(second))"
    }
    if let tripleBox = tryCast(ptr, to: RuntimeTripleBox.self) {
        let first = runtimeElementToString(tripleBox.first)
        let second = runtimeElementToString(tripleBox.second)
        let third = runtimeElementToString(tripleBox.third)
        return "(\(first), \(second), \(third))"
    }
    if let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        let parts = arrayBox.elements.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    return "\(elem)"
}

// MARK: - Collection HOF Helpers (STDLIB-005)

typealias RuntimeCollectionLambda1 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda2 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias ComparatorLambda = RuntimeCollectionLambda2

/// Retains an object and registers it as a runtime handle.
func runtimeRetainObjectHandle(_ object: AnyObject) -> Int {
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(object).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Writes a thrown payload when the caller provided an out-thrown slot.
func runtimeSetThrown(_ outThrown: UnsafeMutablePointer<Int>?, _ value: Int) {
    outThrown?.pointee = value
}

/// Converts boxed primitive values to raw payloads where needed.
func runtimeCollectionUnbox(_ value: Int) -> Int {
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
    return value
}

/// Normalizes truthiness for predicates from raw/boxed Boolean values.
func runtimeCollectionBool(_ value: Int) -> Bool {
    kk_unbox_bool(value) != 0
}

@inline(__always)
func runtimeInvokeCollectionLambda1(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda1.self)
    return fn(closureRaw, value, outThrown)
}

@inline(__always)
func runtimeInvokeCollectionLambda2(
    fnPtr: Int,
    closureRaw: Int,
    lhs: Int,
    rhs: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda2.self)
    return fn(closureRaw, lhs, rhs, outThrown)
}

@inline(__always)
func runtimeInvokeClosureThunk(
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fn = unsafeBitCast(fnPtr, to: KKClosureThunkEntryPoint.self)
    return fn(closureRaw, outThrown)
}

func runtimeCompareValues(_ lhs: Int, _ rhs: Int) -> Int {
    if lhs == rhs {
        return 0
    }
    if let lhsString = runtimeStringFromRawValue(lhs),
       let rhsString = runtimeStringFromRawValue(rhs)
    {
        if lhsString == rhsString {
            return 0
        }
        return lhsString < rhsString ? -1 : 1
    }
    if let lhsScalar = runtimeComparableScalarValue(from: lhs),
       let rhsScalar = runtimeComparableScalarValue(from: rhs)
    {
        switch (lhsScalar, rhsScalar) {
        case let (.floating(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, rhsValue)
        case let (.floating(lhsValue), .integer(rhsValue)):
            return runtimeCompareFloatingValues(lhsValue, Double(rhsValue))
        case let (.integer(lhsValue), .floating(rhsValue)):
            return runtimeCompareFloatingValues(Double(lhsValue), rhsValue)
        case let (.integer(lhsValue), .integer(rhsValue)):
            if lhsValue == rhsValue {
                return 0
            }
            return lhsValue < rhsValue ? -1 : 1
        }
    }
    let lhsRendered = runtimeElementToString(lhs)
    let rhsRendered = runtimeElementToString(rhs)
    if lhsRendered == rhsRendered {
        return 0
    }
    return lhsRendered < rhsRendered ? -1 : 1
}

private enum RuntimeComparableScalarValue {
    case integer(Int)
    case floating(Double)
}

private func runtimeCompareFloatingValues(_ lhs: Double, _ rhs: Double) -> Int {
    if lhs.isNaN {
        return rhs.isNaN ? 0 : 1
    }
    if rhs.isNaN {
        return -1
    }
    if lhs == rhs {
        return 0
    }
    return lhs < rhs ? -1 : 1
}

private func runtimeComparableScalarValue(from raw: Int) -> RuntimeComparableScalarValue? {
    guard raw != runtimeNullSentinelInt else {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return .integer(raw)
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return .integer(raw)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return .floating(Double(floatBox.value))
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return .floating(doubleBox.value)
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return .integer(intBox.value)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return .integer(boolBox.value ? 1 : 0)
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return .integer(longBox.value)
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
        return .integer(charBox.value)
    }
    return nil
}

private func runtimeStringFromRawValue(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return extractString(from: pointer)
}
