import Foundation

// MARK: - JSON Serialization Runtime Support

private let runtimeKSerializerTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.serialization.KSerializer")
private let runtimeKSerializerSerializeSlot = 0
private let runtimeKSerializerDeserializeSlot = 1

final class RuntimeJsonBox {
    let prettyPrint: Bool
    var registeredSerializers: [Int: Int]

    init(prettyPrint: Bool = false, registeredSerializers: [Int: Int] = [:]) {
        self.prettyPrint = prettyPrint
        self.registeredSerializers = registeredSerializers
    }
}

final class RuntimeJsonEncoderBox {
    let jsonRaw: Int
    var encodedValueRaw: Int = runtimeNullSentinelInt
    var hasEncodedValue = false

    init(jsonRaw: Int) {
        self.jsonRaw = jsonRaw
    }
}

final class RuntimeJsonDecoderBox {
    let jsonRaw: Int
    let decodedValueRaw: Int

    init(jsonRaw: Int, decodedValueRaw: Int) {
        self.jsonRaw = jsonRaw
        self.decodedValueRaw = decodedValueRaw
    }
}

// MARK: - Helpers

private func jsonMakeStringRaw(_ value: String) -> Int {
    let utf8 = Array(value.utf8)
    if utf8.isEmpty {
        var emptyByte: UInt8 = 0
        return withUnsafePointer(to: &emptyByte) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, 0))
        }
    }
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

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

private func runtimeJsonBox(from rawValue: Int) -> RuntimeJsonBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeJsonBox.self)
}

private func runtimeJsonEncoderBox(from rawValue: Int) -> RuntimeJsonEncoderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeJsonEncoderBox.self)
}

private func runtimeJsonDecoderBox(from rawValue: Int) -> RuntimeJsonDecoderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeJsonDecoderBox.self)
}

private func runtimeKClassBoxLocal(from rawValue: Int) -> RuntimeKClassBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKClassBox.self)
}

private func runtimeRegisteredInterfaceSlot(objectRaw: Int, interfaceTypeID: Int64) -> Int? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: objectRaw) else {
        return nil
    }
    let objectKey = UInt(bitPattern: ptr)
    return runtimeStorage.withLock { state in
        state.objectInterfaceSlots[objectKey]?[interfaceTypeID]
    }
}

private func runtimeInvokeInterfaceMethod1(
    receiverRaw: Int,
    interfaceTypeID: Int64,
    methodSlot: Int,
    arg: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ifaceSlot = runtimeRegisteredInterfaceSlot(objectRaw: receiverRaw, interfaceTypeID: interfaceTypeID) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "SerializationException: Interface slot lookup failed for receiver \(receiverRaw)."
        )
        return runtimeNullSentinelInt
    }
    let functionRaw = kk_itable_lookup(receiverRaw, ifaceSlot, methodSlot)
    guard functionRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "SerializationException: Interface method lookup failed for receiver \(receiverRaw)."
        )
        return runtimeNullSentinelInt
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint2.self)
    return function(receiverRaw, arg, outThrown)
}

private func runtimeInvokeInterfaceMethod2(
    receiverRaw: Int,
    interfaceTypeID: Int64,
    methodSlot: Int,
    arg1: Int,
    arg2: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ifaceSlot = runtimeRegisteredInterfaceSlot(objectRaw: receiverRaw, interfaceTypeID: interfaceTypeID) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "SerializationException: Interface slot lookup failed for receiver \(receiverRaw)."
        )
        return runtimeNullSentinelInt
    }
    let functionRaw = kk_itable_lookup(receiverRaw, ifaceSlot, methodSlot)
    guard functionRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "SerializationException: Interface method lookup failed for receiver \(receiverRaw)."
        )
        return runtimeNullSentinelInt
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint3.self)
    return function(receiverRaw, arg1, arg2, outThrown)
}

private func runtimeInvokeSerializerSerialize(
    serializerRaw: Int,
    encoderRaw: Int,
    valueRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) {
    _ = runtimeInvokeInterfaceMethod2(
        receiverRaw: serializerRaw,
        interfaceTypeID: runtimeKSerializerTypeID,
        methodSlot: runtimeKSerializerSerializeSlot,
        arg1: encoderRaw,
        arg2: valueRaw,
        outThrown: outThrown
    )
}

private func runtimeInvokeSerializerDeserialize(
    serializerRaw: Int,
    decoderRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeInterfaceMethod1(
        receiverRaw: serializerRaw,
        interfaceTypeID: runtimeKSerializerTypeID,
        methodSlot: runtimeKSerializerDeserializeSlot,
        arg: decoderRaw,
        outThrown: outThrown
    )
}

private func jsonRegisteredSerializer(for valueRaw: Int, in jsonBox: RuntimeJsonBox) -> Int? {
    guard let typeID = runtimeObjectTypeID(rawValue: valueRaw) else {
        return nil
    }
    return jsonBox.registeredSerializers[Int(typeID)]
}

private func runtimeValueToJSON(_ rawValue: Int) -> Any {
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
        return rawValue
    }

    if let box = tryCast(ptr, to: RuntimeStringBox.self) {
        return box.value
    }
    if let box = tryCast(ptr, to: RuntimeIntBox.self) {
        return box.value
    }
    if let box = tryCast(ptr, to: RuntimeLongBox.self) {
        return box.value
    }
    if let box = tryCast(ptr, to: RuntimeBoolBox.self) {
        return box.value
    }
    if let box = tryCast(ptr, to: RuntimeDoubleBox.self) {
        return box.value
    }
    if let box = tryCast(ptr, to: RuntimeFloatBox.self) {
        return Double(box.value)
    }
    if let box = tryCast(ptr, to: RuntimeListBox.self) {
        return box.elements.map { runtimeValueToJSON($0) }
    }
    if let box = tryCast(ptr, to: RuntimeMapBox.self) {
        var dict: [String: Any] = [:]
        for index in 0 ..< box.keys.count {
            let keyRaw = box.keys[index]
            let valueRaw = box.values[index]
            let key = jsonExtractString(from: keyRaw) ?? "\(keyRaw)"
            dict[key] = runtimeValueToJSON(valueRaw)
        }
        return dict
    }
    if let box = tryCast(ptr, to: RuntimePairBox.self) {
        return [runtimeValueToJSON(box.first), runtimeValueToJSON(box.second)]
    }
    if let box = tryCast(ptr, to: RuntimeObjectBox.self) {
        return box.elements.map { runtimeValueToJSON($0) }
    }
    if let box = tryCast(ptr, to: RuntimeArrayBox.self) {
        return box.elements.map { runtimeValueToJSON($0) }
    }

    return rawValue
}

private func jsonToRuntimeValue(_ value: Any) -> Int {
    if value is NSNull {
        return runtimeNullSentinelInt
    }
    if let str = value as? String {
        return jsonMakeStringRaw(str)
    }
    if let bool = value as? Bool {
        return registerRuntimeObject(RuntimeBoolBox(bool))
    }
    if let num = value as? Int {
        return registerRuntimeObject(RuntimeIntBox(num))
    }
    if let num = value as? Double {
        return registerRuntimeObject(RuntimeDoubleBox(num))
    }
    if let num = value as? NSNumber {
        if num.doubleValue == Double(num.intValue) {
            return registerRuntimeObject(RuntimeIntBox(num.intValue))
        }
        return registerRuntimeObject(RuntimeDoubleBox(num.doubleValue))
    }
    if let array = value as? [Any] {
        return registerRuntimeObject(RuntimeListBox(elements: array.map { jsonToRuntimeValue($0) }))
    }
    if let dict = value as? [String: Any] {
        var keys: [Int] = []
        var values: [Int] = []
        for (key, val) in dict {
            keys.append(jsonMakeStringRaw(key))
            values.append(jsonToRuntimeValue(val))
        }
        return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
    }
    return runtimeNullSentinelInt
}

private func encodeJSONString(from valueRaw: Int, jsonBox: RuntimeJsonBox?) -> Int {
    let jsonifiable = runtimeValueToJSON(valueRaw)

    guard JSONSerialization.isValidJSONObject(jsonifiable)
        || jsonifiable is String
        || jsonifiable is NSNumber
        || jsonifiable is Bool
        || jsonifiable is NSNull
    else {
        return jsonMakeStringRaw("null")
    }

    let isTopLevelPrimitive = !(jsonifiable is [Any]) && !(jsonifiable is [String: Any])
    let jsonData: Data

    if isTopLevelPrimitive {
        if let str = jsonifiable as? String {
            do {
                var strOptions: JSONSerialization.WritingOptions = []
                if #available(macOS 10.15, *) {
                    strOptions.insert(.withoutEscapingSlashes)
                }
                let data = try JSONSerialization.data(withJSONObject: [str], options: strOptions)
                if var rendered = String(data: data, encoding: .utf8) {
                    rendered = String(rendered.dropFirst().dropLast())
                    return jsonMakeStringRaw(rendered)
                }
            } catch {}
            return jsonMakeStringRaw("\"\"")
        }
        if jsonifiable is NSNull {
            return jsonMakeStringRaw("null")
        }
        if let boolVal = jsonifiable as? Bool {
            return jsonMakeStringRaw(boolVal ? "true" : "false")
        }
        if let num = jsonifiable as? NSNumber {
            return jsonMakeStringRaw("\(num)")
        }
        return jsonMakeStringRaw("\(jsonifiable)")
    }

    do {
        var options: JSONSerialization.WritingOptions = []
        if jsonBox?.prettyPrint == true {
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

private func parseJSONString(_ stringRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
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

    do {
        let parsed = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        return jsonToRuntimeValue(parsed)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "SerializationException: \(error.localizedDescription)"
        )
        return runtimeNullSentinelInt
    }
}

// MARK: - Json object constructor

@_cdecl("kk_json_default")
public func kk_json_default() -> Int {
    registerRuntimeObject(RuntimeJsonBox(prettyPrint: false))
}

// MARK: - Json.encodeToString(value)

@_cdecl("kk_json_encodeToString")
public func kk_json_encodeToString(_ jsonRaw: Int, _ valueRaw: Int) -> Int {
    if let jsonBox = runtimeJsonBox(from: jsonRaw),
       let serializerRaw = jsonRegisteredSerializer(for: valueRaw, in: jsonBox)
    {
        var thrown = 0
        let encoded = kk_json_encodeWithSerializer(jsonRaw, serializerRaw, valueRaw, &thrown)
        if thrown == 0 {
            return encoded
        }
    }
    return encodeJSONString(from: valueRaw, jsonBox: runtimeJsonBox(from: jsonRaw))
}

@_cdecl("kk_json_encodeWithSerializer")
public func kk_json_encodeWithSerializer(
    _ jsonRaw: Int,
    _ serializerRaw: Int,
    _ valueRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let encoderRaw = registerRuntimeObject(RuntimeJsonEncoderBox(jsonRaw: jsonRaw))
    runtimeInvokeSerializerSerialize(
        serializerRaw: serializerRaw,
        encoderRaw: encoderRaw,
        valueRaw: valueRaw,
        outThrown: outThrown
    )
    if outThrown?.pointee != 0 {
        return jsonMakeStringRaw("null")
    }
    guard let encoder = runtimeJsonEncoderBox(from: encoderRaw), encoder.hasEncodedValue else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "SerializationException: Serializer did not encode a value."
        )
        return jsonMakeStringRaw("null")
    }
    return encodeJSONString(from: encoder.encodedValueRaw, jsonBox: runtimeJsonBox(from: jsonRaw))
}

// MARK: - Json.decodeFromString(string)

@_cdecl("kk_json_decodeFromString")
public func kk_json_decodeFromString(
    _ jsonRaw: Int,
    _ stringRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = jsonRaw
    return parseJSONString(stringRaw, outThrown: outThrown)
}

@_cdecl("kk_json_decodeWithSerializer")
public func kk_json_decodeWithSerializer(
    _ jsonRaw: Int,
    _ serializerRaw: Int,
    _ stringRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let decodedRaw = parseJSONString(stringRaw, outThrown: outThrown)
    if outThrown?.pointee != 0 {
        return runtimeNullSentinelInt
    }
    let decoderRaw = registerRuntimeObject(RuntimeJsonDecoderBox(jsonRaw: jsonRaw, decodedValueRaw: decodedRaw))
    return runtimeInvokeSerializerDeserialize(
        serializerRaw: serializerRaw,
        decoderRaw: decoderRaw,
        outThrown: outThrown
    )
}

// MARK: - Json serializer registry

@_cdecl("kk_json_registerSerializer")
public func kk_json_registerSerializer(
    _ jsonRaw: Int,
    _ kclassRaw: Int,
    _ serializerRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let jsonBox = runtimeJsonBox(from: jsonRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "SerializationException: Invalid Json instance.")
        return jsonRaw
    }
    guard let kclass = runtimeKClassBoxLocal(from: kclassRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "SerializationException: Invalid KClass handle.")
        return jsonRaw
    }
    jsonBox.registeredSerializers[kclass.typeToken] = serializerRaw
    return jsonRaw
}

@_cdecl("kk_json_getRegisteredSerializer")
public func kk_json_getRegisteredSerializer(_ jsonRaw: Int, _ kclassRaw: Int) -> Int {
    guard let jsonBox = runtimeJsonBox(from: jsonRaw),
          let kclass = runtimeKClassBoxLocal(from: kclassRaw)
    else {
        return runtimeNullSentinelInt
    }
    return jsonBox.registeredSerializers[kclass.typeToken] ?? runtimeNullSentinelInt
}

// MARK: - Encoder / Decoder low-level API

@_cdecl("kk_json_encoder_context")
public func kk_json_encoder_context(_ encoderRaw: Int) -> Int {
    runtimeJsonEncoderBox(from: encoderRaw)?.jsonRaw ?? runtimeNullSentinelInt
}

@_cdecl("kk_json_encoder_encodeString")
public func kk_json_encoder_encodeString(_ encoderRaw: Int, _ valueRaw: Int) -> Int {
    guard let encoder = runtimeJsonEncoderBox(from: encoderRaw) else {
        return 0
    }
    encoder.encodedValueRaw = valueRaw
    encoder.hasEncodedValue = true
    return 0
}

@_cdecl("kk_json_encoder_encodeInt")
public func kk_json_encoder_encodeInt(_ encoderRaw: Int, _ valueRaw: Int) -> Int {
    guard let encoder = runtimeJsonEncoderBox(from: encoderRaw) else {
        return 0
    }
    encoder.encodedValueRaw = valueRaw
    encoder.hasEncodedValue = true
    return 0
}

@_cdecl("kk_json_encoder_encodeBoolean")
public func kk_json_encoder_encodeBoolean(_ encoderRaw: Int, _ valueRaw: Int) -> Int {
    guard let encoder = runtimeJsonEncoderBox(from: encoderRaw) else {
        return 0
    }
    encoder.encodedValueRaw = valueRaw
    encoder.hasEncodedValue = true
    return 0
}

@_cdecl("kk_json_encoder_encodeDouble")
public func kk_json_encoder_encodeDouble(_ encoderRaw: Int, _ valueRaw: Int) -> Int {
    guard let encoder = runtimeJsonEncoderBox(from: encoderRaw) else {
        return 0
    }
    encoder.encodedValueRaw = valueRaw
    encoder.hasEncodedValue = true
    return 0
}

@_cdecl("kk_json_encoder_encodeNull")
public func kk_json_encoder_encodeNull(_ encoderRaw: Int) -> Int {
    guard let encoder = runtimeJsonEncoderBox(from: encoderRaw) else {
        return 0
    }
    encoder.encodedValueRaw = runtimeNullSentinelInt
    encoder.hasEncodedValue = true
    return 0
}

@_cdecl("kk_json_encoder_encodeValue")
public func kk_json_encoder_encodeValue(_ encoderRaw: Int, _ valueRaw: Int) -> Int {
    guard let encoder = runtimeJsonEncoderBox(from: encoderRaw) else {
        return 0
    }
    encoder.encodedValueRaw = valueRaw
    encoder.hasEncodedValue = true
    return 0
}

@_cdecl("kk_json_decoder_context")
public func kk_json_decoder_context(_ decoderRaw: Int) -> Int {
    runtimeJsonDecoderBox(from: decoderRaw)?.jsonRaw ?? runtimeNullSentinelInt
}

@_cdecl("kk_json_decoder_decodeString")
public func kk_json_decoder_decodeString(_ decoderRaw: Int) -> Int {
    runtimeJsonDecoderBox(from: decoderRaw)?.decodedValueRaw ?? runtimeNullSentinelInt
}

@_cdecl("kk_json_decoder_decodeInt")
public func kk_json_decoder_decodeInt(_ decoderRaw: Int) -> Int {
    runtimeJsonDecoderBox(from: decoderRaw)?.decodedValueRaw ?? 0
}

@_cdecl("kk_json_decoder_decodeBoolean")
public func kk_json_decoder_decodeBoolean(_ decoderRaw: Int) -> Int {
    runtimeJsonDecoderBox(from: decoderRaw)?.decodedValueRaw ?? 0
}

@_cdecl("kk_json_decoder_decodeDouble")
public func kk_json_decoder_decodeDouble(_ decoderRaw: Int) -> Int {
    runtimeJsonDecoderBox(from: decoderRaw)?.decodedValueRaw ?? 0
}

@_cdecl("kk_json_decoder_decodeValue")
public func kk_json_decoder_decodeValue(_ decoderRaw: Int) -> Int {
    runtimeJsonDecoderBox(from: decoderRaw)?.decodedValueRaw ?? runtimeNullSentinelInt
}

// MARK: - Json.encodeToString(map) convenience

@_cdecl("kk_json_encodeMapToString")
public func kk_json_encodeMapToString(_ jsonRaw: Int, _ mapRaw: Int) -> Int {
    kk_json_encodeToString(jsonRaw, mapRaw)
}
