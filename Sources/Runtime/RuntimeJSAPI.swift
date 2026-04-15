import Foundation

// MARK: - STDLIB-JS-167: JavaScript-specific API runtime stubs
//
// This file provides runtime support for Kotlin/JS APIs when compiled by KSwiftK.
// On native targets these APIs are no-ops or best-effort emulations because there
// is no JavaScript engine available.  They exist so that code annotated with
// @JsName / @JsExport / @JsModule, or code that uses JsObject / JsArray / dynamic,
// can be compiled and tested without a browser.
//
// Implemented:
//   - dynamic type support  (kk_js_dynamic_*)
//   - js() inline-JavaScript stub  (kk_js_inline)
//   - JsObject / JsArray box types and entry points
//   - DOM stubs: document, window, console
//   - JSON.stringify / JSON.parse analogues
//   - Promise interop  (kk_js_promise_*)
//   - @JsName / @JsExport / @JsModule annotation markers

// MARK: - Box types

/// A runtime box representing a JavaScript `dynamic` value.
/// On native targets we store arbitrary data as a dictionary of string keys to
/// opaque Int handles, which mirrors the property-bag nature of JS objects.
final class RuntimeJsDynamicBox: @unchecked Sendable {
    var properties: [String: Int] = [:]
    var arrayElements: [Int] = []
    var stringValue: String?
    var numberValue: Double?
    var boolValue: Bool?
    var isArray: Bool = false
    var isNull: Bool = false
    var isUndefined: Bool = true

    init() {}

    init(string: String) {
        self.stringValue = string
        self.isUndefined = false
    }

    init(number: Double) {
        self.numberValue = number
        self.isUndefined = false
    }

    init(bool: Bool) {
        self.boolValue = bool
        self.isUndefined = false
    }

    init(array: [Int]) {
        self.arrayElements = array
        self.isArray = true
        self.isUndefined = false
    }

    static func makeUndefined() -> RuntimeJsDynamicBox {
        RuntimeJsDynamicBox()
    }

    static func makeNull() -> RuntimeJsDynamicBox {
        let b = RuntimeJsDynamicBox()
        b.isNull = true
        b.isUndefined = false
        return b
    }

    /// Produce a JSON-like string representation of this value.
    func toJsonString() -> String {
        if isUndefined { return "undefined" }
        if isNull { return "null" }
        if let s = stringValue { return "\"\(s.jsEscaped)\"" }
        if let n = numberValue {
            if n.truncatingRemainder(dividingBy: 1) == 0, !n.isInfinite, !n.isNaN {
                return String(Int64(n))
            }
            return String(n)
        }
        if let b = boolValue { return b ? "true" : "false" }
        if isArray {
            let inner = arrayElements.map { jsStringForRaw($0) }.joined(separator: ",")
            return "[\(inner)]"
        }
        // Object
        let pairs = properties.sorted(by: { $0.key < $1.key }).map { k, v in
            "\"\(k.jsEscaped)\":\(jsStringForRaw(v))"
        }.joined(separator: ",")
        return "{\(pairs)}"
    }
}

/// Produce a JS-style string for a raw runtime Int value.
private func jsStringForRaw(_ raw: Int) -> String {
    if raw == runtimeNullSentinelInt { return "null" }
    if raw == 0 { return "undefined" }
    if let ptr = UnsafeMutableRawPointer(bitPattern: raw),
       runtimeIsObjectPointer(ptr) {
        if let box = tryCast(ptr, to: RuntimeJsDynamicBox.self) {
            return box.toJsonString()
        }
        if let strBox = tryCast(ptr, to: RuntimeStringBox.self) {
            return "\"\(strBox.value.jsEscaped)\""
        }
    }
    return String(raw)
}

private extension String {
    /// Minimal JSON string escaping.
    var jsEscaped: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Box registration helpers

private func runtimeAllocateDynamicBox(_ box: RuntimeJsDynamicBox) -> Int {
    let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: pointer))
    }
    return Int(bitPattern: pointer)
}

private func runtimeJsDynamicBox(from raw: Int) -> RuntimeJsDynamicBox? {
    guard raw != runtimeNullSentinelInt, raw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else { return nil }
    guard runtimeIsObjectPointer(ptr) else { return nil }
    return tryCast(ptr, to: RuntimeJsDynamicBox.self)
}

private func runtimeIsObjectPointer(_ ptr: UnsafeMutableRawPointer) -> Bool {
    runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
}

// MARK: - dynamic type support

/// Create an undefined `dynamic` value.
/// Kotlin: val x: dynamic = undefined
@_cdecl("kk_js_dynamic_undefined")
public func kk_js_dynamic_undefined() -> Int {
    runtimeAllocateDynamicBox(RuntimeJsDynamicBox())
}

/// Create a null `dynamic` value.
@_cdecl("kk_js_dynamic_null")
public func kk_js_dynamic_null() -> Int {
    runtimeAllocateDynamicBox(.makeNull())
}

/// Wrap a runtime string as `dynamic`.
@_cdecl("kk_js_dynamic_from_string")
public func kk_js_dynamic_from_string(_ rawString: Int) -> Int {
    let str: String
    if let ptr = UnsafeMutableRawPointer(bitPattern: rawString),
       runtimeIsObjectPointer(ptr),
       let box = tryCast(ptr, to: RuntimeStringBox.self) {
        str = box.value
    } else {
        str = ""
    }
    return runtimeAllocateDynamicBox(RuntimeJsDynamicBox(string: str))
}

/// Wrap a Double (bit-pattern Int) as `dynamic`.
@_cdecl("kk_js_dynamic_from_double")
public func kk_js_dynamic_from_double(_ bits: Int) -> Int {
    let value = Double(bitPattern: UInt64(bitPattern: Int64(bits)))
    return runtimeAllocateDynamicBox(RuntimeJsDynamicBox(number: value))
}

/// Wrap a boolean (0/1) as `dynamic`.
@_cdecl("kk_js_dynamic_from_bool")
public func kk_js_dynamic_from_bool(_ value: Int) -> Int {
    runtimeAllocateDynamicBox(RuntimeJsDynamicBox(bool: value != 0))
}

/// Get a named property from a `dynamic` value.
/// Returns null sentinel when property does not exist.
@_cdecl("kk_js_dynamic_get_property")
public func kk_js_dynamic_get_property(_ dynamicRaw: Int, _ keyRaw: Int) -> Int {
    guard let box = runtimeJsDynamicBox(from: dynamicRaw) else {
        return runtimeNullSentinelInt
    }
    let key: String
    if let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       runtimeIsObjectPointer(ptr),
       let strBox = tryCast(ptr, to: RuntimeStringBox.self) {
        key = strBox.value
    } else {
        return runtimeNullSentinelInt
    }
    return box.properties[key] ?? runtimeNullSentinelInt
}

/// Set a named property on a `dynamic` value.
@_cdecl("kk_js_dynamic_set_property")
public func kk_js_dynamic_set_property(_ dynamicRaw: Int, _ keyRaw: Int, _ value: Int) {
    guard let box = runtimeJsDynamicBox(from: dynamicRaw) else { return }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
          runtimeIsObjectPointer(ptr),
          let strBox = tryCast(ptr, to: RuntimeStringBox.self)
    else { return }
    box.properties[strBox.value] = value
}

/// Check whether a `dynamic` value is null or undefined.
/// Returns 1 (true) when null/undefined, 0 otherwise.
@_cdecl("kk_js_dynamic_is_null_or_undefined")
public func kk_js_dynamic_is_null_or_undefined(_ dynamicRaw: Int) -> Int {
    guard let box = runtimeJsDynamicBox(from: dynamicRaw) else { return 1 }
    return (box.isNull || box.isUndefined) ? 1 : 0
}

// MARK: - js() inline JavaScript stub

/// Stub for Kotlin's `js(code)` function.
/// On native targets there is no JS engine, so we return `undefined`.
/// Kotlin: val x = js("someJSExpression")
@_cdecl("kk_js_inline")
public func kk_js_inline(_ codeRaw: Int) -> Int {
    // On a native target we cannot execute JavaScript.
    // Return an undefined dynamic box so callers do not crash on null dereference.
    kk_js_dynamic_undefined()
}

// MARK: - JsObject

/// Create a new empty JsObject (property bag).
/// Kotlin: val obj = JsObject()
@_cdecl("kk_js_object_new")
public func kk_js_object_new() -> Int {
    let box = RuntimeJsDynamicBox()
    box.isUndefined = false
    return runtimeAllocateDynamicBox(box)
}

/// Get a property from a JsObject.  Delegates to kk_js_dynamic_get_property.
@_cdecl("kk_js_object_get")
public func kk_js_object_get(_ objectRaw: Int, _ keyRaw: Int) -> Int {
    kk_js_dynamic_get_property(objectRaw, keyRaw)
}

/// Set a property on a JsObject.  Delegates to kk_js_dynamic_set_property.
@_cdecl("kk_js_object_set")
public func kk_js_object_set(_ objectRaw: Int, _ keyRaw: Int, _ value: Int) {
    kk_js_dynamic_set_property(objectRaw, keyRaw, value)
}

/// Check whether a JsObject has a given property key.
/// Returns 1 (true) if the key exists, 0 otherwise.
@_cdecl("kk_js_object_has")
public func kk_js_object_has(_ objectRaw: Int, _ keyRaw: Int) -> Int {
    guard let box = runtimeJsDynamicBox(from: objectRaw) else { return 0 }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
          runtimeIsObjectPointer(ptr),
          let strBox = tryCast(ptr, to: RuntimeStringBox.self)
    else { return 0 }
    return box.properties[strBox.value] != nil ? 1 : 0
}

/// Delete a property from a JsObject.
@_cdecl("kk_js_object_delete")
public func kk_js_object_delete(_ objectRaw: Int, _ keyRaw: Int) {
    guard let box = runtimeJsDynamicBox(from: objectRaw) else { return }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
          runtimeIsObjectPointer(ptr),
          let strBox = tryCast(ptr, to: RuntimeStringBox.self)
    else { return }
    box.properties.removeValue(forKey: strBox.value)
}

// MARK: - JsArray

/// Create a new empty JsArray.
/// Kotlin: val arr = JsArray<Int>()
@_cdecl("kk_js_array_new")
public func kk_js_array_new() -> Int {
    let box = RuntimeJsDynamicBox(array: [])
    return runtimeAllocateDynamicBox(box)
}

/// Return the length of a JsArray.
@_cdecl("kk_js_array_length")
public func kk_js_array_length(_ arrayRaw: Int) -> Int {
    guard let box = runtimeJsDynamicBox(from: arrayRaw), box.isArray else { return 0 }
    return box.arrayElements.count
}

/// Get an element by index from a JsArray.  Returns null sentinel on out-of-bounds.
@_cdecl("kk_js_array_get")
public func kk_js_array_get(_ arrayRaw: Int, _ index: Int) -> Int {
    guard let box = runtimeJsDynamicBox(from: arrayRaw), box.isArray else {
        return runtimeNullSentinelInt
    }
    guard index >= 0, index < box.arrayElements.count else {
        return runtimeNullSentinelInt
    }
    return box.arrayElements[index]
}

/// Set an element by index in a JsArray.  Grows the array if necessary.
@_cdecl("kk_js_array_set")
public func kk_js_array_set(_ arrayRaw: Int, _ index: Int, _ value: Int) {
    guard let box = runtimeJsDynamicBox(from: arrayRaw), box.isArray else { return }
    guard index >= 0 else { return }
    if index >= box.arrayElements.count {
        box.arrayElements.append(
            contentsOf: Array(repeating: runtimeNullSentinelInt, count: index - box.arrayElements.count + 1)
        )
    }
    box.arrayElements[index] = value
}

/// Append an element to a JsArray.
@_cdecl("kk_js_array_push")
public func kk_js_array_push(_ arrayRaw: Int, _ value: Int) {
    guard let box = runtimeJsDynamicBox(from: arrayRaw), box.isArray else { return }
    box.arrayElements.append(value)
}

// MARK: - DOM stubs: console

/// Stub for `console.log(message)`.
/// On native targets we write to stdout, matching Kotlin/JS behavior.
@_cdecl("kk_console_log")
public func kk_console_log(_ messageRaw: Int) {
    let text = jsStringForRaw(messageRaw)
    print(text)
}

/// Stub for `console.error(message)`.
@_cdecl("kk_console_error")
public func kk_console_error(_ messageRaw: Int) {
    let text = jsStringForRaw(messageRaw)
    FileHandle.standardError.write(Data("\(text)\n".utf8))
}

/// Stub for `console.warn(message)`.
@_cdecl("kk_console_warn")
public func kk_console_warn(_ messageRaw: Int) {
    let text = jsStringForRaw(messageRaw)
    FileHandle.standardError.write(Data("WARN: \(text)\n".utf8))
}

// MARK: - DOM stubs: document

/// Stub for `document.getElementById(id)`.
/// Returns `undefined` because there is no DOM on native targets.
@_cdecl("kk_document_get_element_by_id")
public func kk_document_get_element_by_id(_ idRaw: Int) -> Int {
    kk_js_dynamic_undefined()
}

/// Stub for `document.createElement(tagName)`.
@_cdecl("kk_document_create_element")
public func kk_document_create_element(_ tagNameRaw: Int) -> Int {
    kk_js_object_new()
}

/// Stub for `document.title` getter.
@_cdecl("kk_document_get_title")
public func kk_document_get_title() -> Int {
    kk_js_dynamic_from_string(runtimeNullSentinelInt)
}

/// Stub for `document.title` setter. No-op on native.
@_cdecl("kk_document_set_title")
public func kk_document_set_title(_ titleRaw: Int) {
    // No-op on native targets.
}

// MARK: - DOM stubs: window

/// Stub for `window.alert(message)`. Prints to stdout on native.
@_cdecl("kk_window_alert")
public func kk_window_alert(_ messageRaw: Int) {
    kk_console_log(messageRaw)
}

/// Stub for `window.location.href` getter.
@_cdecl("kk_window_location_href")
public func kk_window_location_href() -> Int {
    kk_js_dynamic_undefined()
}

// MARK: - JSON.stringify / JSON.parse analogues

/// Serialize a runtime value to a JSON string.
/// Kotlin: JSON.stringify(value)
@_cdecl("kk_json_stringify")
public func kk_json_stringify(_ rawValue: Int) -> Int {
    let json = jsStringForRaw(rawValue)
    return runtimeMakeStringRawJS(json)
}

/// Parse a JSON string into a dynamic value.
/// On native targets we do a best-effort parse into a RuntimeJsDynamicBox.
/// Kotlin: JSON.parse<T>(text)
@_cdecl("kk_json_parse")
public func kk_json_parse(_ rawString: Int) -> Int {
    let text: String
    if let ptr = UnsafeMutableRawPointer(bitPattern: rawString),
       runtimeIsObjectPointer(ptr),
       let strBox = tryCast(ptr, to: RuntimeStringBox.self) {
        text = strBox.value
    } else {
        return kk_js_dynamic_null()
    }

    guard let data = text.data(using: .utf8),
          let jsonObj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else {
        return kk_js_dynamic_null()
    }

    return runtimeJsValueFromAny(jsonObj)
}

// MARK: - Promise interop

/// Box type for a native stub of a Kotlin/JS Promise.
final class RuntimeJsPromiseBox: @unchecked Sendable {
    enum State {
        case pending
        case fulfilled(Int)
        case rejected(Int)
    }
    var state: State = .pending
    var fulfillCallbacks: [(Int) -> Void] = []
    var rejectCallbacks: [(Int) -> Void] = []

    func resolve(with value: Int) {
        guard case .pending = state else { return }
        state = .fulfilled(value)
        fulfillCallbacks.forEach { $0(value) }
        fulfillCallbacks = []
        rejectCallbacks = []
    }

    func reject(with reason: Int) {
        guard case .pending = state else { return }
        state = .rejected(reason)
        rejectCallbacks.forEach { $0(reason) }
        fulfillCallbacks = []
        rejectCallbacks = []
    }
}

private func runtimeJsPromiseBox(from raw: Int) -> RuntimeJsPromiseBox? {
    guard raw != runtimeNullSentinelInt, raw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else { return nil }
    guard runtimeIsObjectPointer(ptr) else { return nil }
    return tryCast(ptr, to: RuntimeJsPromiseBox.self)
}

private func runtimeAllocatePromiseBox(_ box: RuntimeJsPromiseBox) -> Int {
    let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: pointer))
    }
    return Int(bitPattern: pointer)
}

/// Create a new pending Promise.
/// Kotlin: Promise<T> { resolve, reject -> ... }
@_cdecl("kk_js_promise_new")
public func kk_js_promise_new() -> Int {
    runtimeAllocatePromiseBox(RuntimeJsPromiseBox())
}

/// Resolve a Promise with a value.
@_cdecl("kk_js_promise_resolve")
public func kk_js_promise_resolve(_ promiseRaw: Int, _ value: Int) {
    runtimeJsPromiseBox(from: promiseRaw)?.resolve(with: value)
}

/// Reject a Promise with a reason (usually a throwable handle).
@_cdecl("kk_js_promise_reject")
public func kk_js_promise_reject(_ promiseRaw: Int, _ reason: Int) {
    runtimeJsPromiseBox(from: promiseRaw)?.reject(with: reason)
}

/// Return 1 if the Promise is fulfilled, 0 otherwise.
@_cdecl("kk_js_promise_is_fulfilled")
public func kk_js_promise_is_fulfilled(_ promiseRaw: Int) -> Int {
    guard let box = runtimeJsPromiseBox(from: promiseRaw) else { return 0 }
    if case .fulfilled = box.state { return 1 }
    return 0
}

/// Return 1 if the Promise is rejected, 0 otherwise.
@_cdecl("kk_js_promise_is_rejected")
public func kk_js_promise_is_rejected(_ promiseRaw: Int) -> Int {
    guard let box = runtimeJsPromiseBox(from: promiseRaw) else { return 0 }
    if case .rejected = box.state { return 1 }
    return 0
}

/// Get the fulfilled value of a Promise. Returns null sentinel if not fulfilled.
@_cdecl("kk_js_promise_get_value")
public func kk_js_promise_get_value(_ promiseRaw: Int) -> Int {
    guard let box = runtimeJsPromiseBox(from: promiseRaw),
          case let .fulfilled(v) = box.state
    else { return runtimeNullSentinelInt }
    return v
}

/// Get the rejection reason. Returns null sentinel if not rejected.
@_cdecl("kk_js_promise_get_reason")
public func kk_js_promise_get_reason(_ promiseRaw: Int) -> Int {
    guard let box = runtimeJsPromiseBox(from: promiseRaw),
          case let .rejected(r) = box.state
    else { return runtimeNullSentinelInt }
    return r
}

// MARK: - @JsName / @JsExport / @JsModule annotation markers
//
// On native targets these annotations only affect the name used when the
// Kotlin/JS backend generates JavaScript; they have no runtime effect.
// We expose no-op entry points so that compiled code that calls runtime hooks
// for annotation processing does not link against missing symbols.

/// No-op marker called when @JsName is applied to a declaration.
/// `nameRaw` is the raw runtime handle of the desired JS name string.
@_cdecl("kk_annotation_js_name")
public func kk_annotation_js_name(_ nameRaw: Int) {
    // No-op on native targets.
}

/// No-op marker called when @JsExport is applied to a declaration.
@_cdecl("kk_annotation_js_export")
public func kk_annotation_js_export() {
    // No-op on native targets.
}

/// No-op marker called when @JsModule is applied to a declaration.
/// `moduleRaw` is the raw runtime handle of the module identifier string.
@_cdecl("kk_annotation_js_module")
public func kk_annotation_js_module(_ moduleRaw: Int) {
    // No-op on native targets.
}

// MARK: - Private helpers

/// Build a runtime string from a Swift String.
/// This mirrors the private `runtimeMakeStringRaw` used in other files.
private func runtimeMakeStringRawJS(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

/// Recursively convert a JSONSerialization result into a RuntimeJsDynamicBox tree.
private func runtimeJsValueFromAny(_ any: Any) -> Int {
    switch any {
    case let str as String:
        let box = RuntimeJsDynamicBox(string: str)
        return runtimeAllocateDynamicBox(box)
    case let num as NSNumber:
        // Bool comes back as NSNumber; use objCType to distinguish.
        let typeStr = String(cString: num.objCType)
        if typeStr == "c" || typeStr == "B" {
            return runtimeAllocateDynamicBox(RuntimeJsDynamicBox(bool: num.boolValue))
        }
        return runtimeAllocateDynamicBox(RuntimeJsDynamicBox(number: num.doubleValue))
    case is NSNull:
        return kk_js_dynamic_null()
    case let arr as [Any]:
        let elements = arr.map { runtimeJsValueFromAny($0) }
        let box = RuntimeJsDynamicBox(array: elements)
        return runtimeAllocateDynamicBox(box)
    case let dict as [String: Any]:
        let box = RuntimeJsDynamicBox()
        box.isUndefined = false
        for (k, v) in dict {
            box.properties[k] = runtimeJsValueFromAny(v)
        }
        return runtimeAllocateDynamicBox(box)
    default:
        return kk_js_dynamic_undefined()
    }
}
