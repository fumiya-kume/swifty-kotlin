import Foundation

// MARK: - JSON Serialization Runtime Support (STDLIB-SER-132)
// Implements kotlinx.serialization.json.Json.encodeToString() and Json.decodeFromString()
// using Swift Foundation's JSONSerialization.

// MARK: - Internal Box

/// Internal box holding the Json encoder/decoder singleton.
/// This corresponds to the `Json` object in Kotlin's kotlinx.serialization.json.
final class RuntimeJsonBox {
    // Default configuration: pretty-print off, ignore unknown keys on.
    let prettyPrint: Bool

    init(prettyPrint: Bool = false) {
        self.prettyPrint = prettyPrint
    }
}

// MARK: - Helpers

/// Make a runtime string Int from a Swift String.
private func jsonMakeStringRaw(_ value: String) -> Int {
    if value.isEmpty {
        return value.withCString { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, 0))
        }
    }
    let utf8 = Array(value.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

/// Extract a Swift String from a runtime raw value.
private func jsonExtractString(from rawValue: Int) -> String? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeStringBox.self)?.value
}

/// Convert a runtime value (opaque Int) to a Swift Any suitable for JSONSerialization.
private func runtimeValueToJSON(_ rawValue: Int) -> Any {
    // Null sentinel
    if rawValue == runtimeNullSentinelInt || rawValue == 0 {
        return NSNull()
    }

    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return rawValue
    }

    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }

    guard isObjectPointer else {
        // Raw integer (unboxed Int/Long/Bool/Char)
        return rawValue
    }

    // String
    if let box = tryCast(ptr, to: RuntimeStringBox.self) {
        return box.value
    }

    // Int box
    if let box = tryCast(ptr, to: RuntimeIntBox.self) {
        return box.value
    }

    // Long box
    if let box = tryCast(ptr, to: RuntimeLongBox.self) {
        return box.value
    }

    // Bool box
    if let box = tryCast(ptr, to: RuntimeBoolBox.self) {
        return box.value
    }

    // Double box
    if let box = tryCast(ptr, to: RuntimeDoubleBox.self) {
        return box.value
    }

    // Float box
    if let box = tryCast(ptr, to: RuntimeFloatBox.self) {
        return Double(box.value)
    }

    // List
    if let box = tryCast(ptr, to: RuntimeListBox.self) {
        return box.elements.map { runtimeValueToJSON($0) }
    }

    // Map
    if let box = tryCast(ptr, to: RuntimeMapBox.self) {
        var dict: [String: Any] = [:]
        for index in 0..<box.keys.count {
            let keyRaw = box.keys[index]
            let valueRaw = box.values[index]
            let key: String
            if let k = jsonExtractString(from: keyRaw) {
                key = k
            } else {
                key = "\(keyRaw)"
            }
            dict[key] = runtimeValueToJSON(valueRaw)
        }
        return dict
    }

    // Pair -> 2-element array
    if let box = tryCast(ptr, to: RuntimePairBox.self) {
        return [runtimeValueToJSON(box.first), runtimeValueToJSON(box.second)]
    }

    // RuntimeObjectBox: serialize fields array as array
    if let box = tryCast(ptr, to: RuntimeObjectBox.self) {
        return box.elements.map { runtimeValueToJSON($0) }
    }

    // RuntimeArrayBox: generic array
    if let box = tryCast(ptr, to: RuntimeArrayBox.self) {
        return box.elements.map { runtimeValueToJSON($0) }
    }

    // Fallback: treat raw pointer as integer
    return rawValue
}

/// Convert a JSONSerialization-parsed Any into a runtime raw value.
/// Strings → RuntimeStringBox (intptr_t)
/// Numbers → boxed Int/RuntimeDoubleBox (integer 0 is boxed to avoid null confusion)
/// Booleans → RuntimeBoolBox (boxed to distinguish false from null)
/// Arrays → RuntimeListBox
/// Dicts → RuntimeMapBox
/// Null → runtimeNullSentinelInt
private func jsonToRuntimeValue(_ value: Any) -> Int {
    if value is NSNull {
        return runtimeNullSentinelInt
    }
    if let str = value as? String {
        return jsonMakeStringRaw(str)
    }
    if let bool = value as? Bool {
        // Box booleans so that false (raw 0) is distinguishable from null (raw 0).
        let box = RuntimeBoolBox(bool)
        return registerRuntimeObject(box)
    }
    if let num = value as? Int {
        // Box integer 0 so it is distinguishable from the null sentinel (raw 0).
        let box = RuntimeIntBox(num)
        return registerRuntimeObject(box)
    }
    if let num = value as? Double {
        let box = RuntimeDoubleBox(num)
        return registerRuntimeObject(box)
    }
    if let num = value as? NSNumber {
        // Could be int or double depending on JSON value
        if num.doubleValue == Double(num.intValue) {
            let box = RuntimeIntBox(num.intValue)
            return registerRuntimeObject(box)
        }
        let box = RuntimeDoubleBox(num.doubleValue)
        return registerRuntimeObject(box)
    }
    if let array = value as? [Any] {
        let elements = array.map { jsonToRuntimeValue($0) }
        let list = RuntimeListBox(elements: elements)
        return registerRuntimeObject(list)
    }
    if let dict = value as? [String: Any] {
        var keys: [Int] = []
        var values: [Int] = []
        for (key, val) in dict {
            keys.append(jsonMakeStringRaw(key))
            values.append(jsonToRuntimeValue(val))
        }
        let map = RuntimeMapBox(keys: keys, values: values)
        return registerRuntimeObject(map)
    }
    return runtimeNullSentinelInt
}

// MARK: - Json object constructor

/// Create and return the default Json instance (singleton-like).
@_cdecl("kk_json_default")
public func kk_json_default() -> Int {
    let box = RuntimeJsonBox(prettyPrint: false)
    return registerRuntimeObject(box)
}

// MARK: - Json.encodeToString(value)

/// Encode any Kotlin runtime value to a JSON string.
/// Corresponds to Json.encodeToString(serializer, value) with auto-detection.
@_cdecl("kk_json_encodeToString")
public func kk_json_encodeToString(_ jsonRaw: Int, _ valueRaw: Int) -> Int {
    let jsonifiable = runtimeValueToJSON(valueRaw)

    guard JSONSerialization.isValidJSONObject(jsonifiable) ||
          jsonifiable is String ||
          jsonifiable is NSNumber ||
          jsonifiable is Bool ||
          jsonifiable is NSNull
    else {
        return jsonMakeStringRaw("null")
    }

    // Wrap primitives in an array for JSONSerialization, then unwrap
    let isTopLevelPrimitive = !(jsonifiable is [Any]) && !(jsonifiable is [String: Any])

    let jsonData: Data
    if isTopLevelPrimitive {
        // For primitives, produce the JSON representation directly
        if let str = jsonifiable as? String {
            // Produce JSON-encoded string with quotes
            do {
                var strOptions: JSONSerialization.WritingOptions = []
                if #available(macOS 10.15, *) {
                    strOptions.insert(.withoutEscapingSlashes)
                }
                let data = try JSONSerialization.data(withJSONObject: [str], options: strOptions)
                // data is ["value"], strip brackets and unwrap
                if var str = String(data: data, encoding: .utf8) {
                    str = String(str.dropFirst().dropLast())
                    return jsonMakeStringRaw(str)
                }
            } catch {}
            return jsonMakeStringRaw("\"\"")
        } else if jsonifiable is NSNull {
            return jsonMakeStringRaw("null")
        } else if let boolVal = jsonifiable as? Bool {
            return jsonMakeStringRaw(boolVal ? "true" : "false")
        } else if let num = jsonifiable as? NSNumber {
            return jsonMakeStringRaw("\(num)")
        } else {
            return jsonMakeStringRaw("\(jsonifiable)")
        }
    }

    do {
        let box = runtimeStorage.withLock { state -> RuntimeJsonBox? in
            guard let ptr = UnsafeMutableRawPointer(bitPattern: jsonRaw),
                  state.objectPointers.contains(UInt(bitPattern: ptr))
            else {
                return nil
            }
            return tryCast(ptr, to: RuntimeJsonBox.self)
        }

        var options: JSONSerialization.WritingOptions = []
        if box?.prettyPrint == true {
            options.insert(.prettyPrinted)
        }
        if #available(macOS 10.15, *) {
            options.insert(.withoutEscapingSlashes)
        }

        jsonData = try JSONSerialization.data(withJSONObject: jsonifiable, options: options)
    } catch {
        return jsonMakeStringRaw("null")
    }

    let jsonString = String(data: jsonData, encoding: .utf8) ?? "null"
    return jsonMakeStringRaw(jsonString)
}

// MARK: - Json.decodeFromString(string)

/// Decode a JSON string into a Kotlin runtime value.
/// Strings → RuntimeStringBox
/// Objects → RuntimeMapBox<String, Any>
/// Arrays → RuntimeListBox
/// Numbers → Int (integers) or RuntimeDoubleBox (floats)
/// Booleans → 1/0
/// Null → runtimeNullSentinelInt
@_cdecl("kk_json_decodeFromString")
public func kk_json_decodeFromString(
    _ jsonRaw: Int,
    _ stringRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0

    guard let jsonString = jsonExtractString(from: stringRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "SerializationException: Input string is null or invalid"
        )
        return runtimeNullSentinelInt
    }

    guard let data = jsonString.data(using: .utf8) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "SerializationException: Cannot convert string to UTF-8 data"
        )
        return runtimeNullSentinelInt
    }

    let parsed: Any
    do {
        parsed = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "SerializationException: \(error.localizedDescription)"
        )
        return runtimeNullSentinelInt
    }

    return jsonToRuntimeValue(parsed)
}

// MARK: - Json.encodeToString(map) convenience

/// Encode a Kotlin Map to a JSON string.
/// This is a thin wrapper used when the user passes a Map directly.
@_cdecl("kk_json_encodeMapToString")
public func kk_json_encodeMapToString(_ jsonRaw: Int, _ mapRaw: Int) -> Int {
    return kk_json_encodeToString(jsonRaw, mapRaw)
}
