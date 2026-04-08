import Foundation

// MARK: - JVM Preview Features Runtime (STDLIB-JVM-166)
//
// Provides runtime support for Java preview features as modelled in Kotlin/JVM interop:
//   - @PreviewFeature annotation simulation
//   - Sealed class hierarchy interop (Java sealed classes)
//   - @JvmRecord annotation / Java Records support
//   - Pattern matching for instanceof interop
//   - Switch expressions support
//   - Text blocks (multi-line string literals)

// MARK: - Preview Feature Annotation State

/// Models the opt-in requirement for a Kotlin/JVM preview-feature API.
enum RuntimePreviewStatus {
    case stable
    case preview(since: String)
    case experimental(since: String)
}

final class RuntimePreviewFeatureBox {
    let featureName: String
    let status: RuntimePreviewStatus
    var enabled: Bool

    init(featureName: String, status: RuntimePreviewStatus, enabled: Bool = false) {
        self.featureName = featureName
        self.status = status
        self.enabled = enabled
    }
}

private let previewFeatureRegistry = NSLock()
private nonisolated(unsafe) var previewFeatureStore: [String: RuntimePreviewFeatureBox] = [:]

private func withPreviewFeatureRegistry<T>(_ body: () -> T) -> T {
    previewFeatureRegistry.lock()
    defer { previewFeatureRegistry.unlock() }
    return body()
}

@_cdecl("kk_jvm_preview_register")
public func kk_jvm_preview_register(_ nameRaw: Int, _ statusRaw: Int, _ enabledRaw: Int) -> Int {
    guard let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)),
          !name.isEmpty
    else {
        return 0
    }
    let sinceLabel: String
    if let sincePtr = UnsafeMutableRawPointer(bitPattern: statusRaw),
       let s = extractString(from: sincePtr), !s.isEmpty {
        sinceLabel = s
    } else {
        sinceLabel = ""
    }
    let status: RuntimePreviewStatus = sinceLabel.isEmpty
        ? .stable
        : .preview(since: sinceLabel)
    let enabled = enabledRaw != 0
    withPreviewFeatureRegistry {
        previewFeatureStore[name] = RuntimePreviewFeatureBox(
            featureName: name,
            status: status,
            enabled: enabled
        )
    }
    return 0
}

@_cdecl("kk_jvm_preview_is_enabled")
public func kk_jvm_preview_is_enabled(_ nameRaw: Int) -> Int {
    guard let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) else {
        return 0
    }
    return withPreviewFeatureRegistry {
        previewFeatureStore[name]?.enabled ?? false
    } ? 1 : 0
}

@_cdecl("kk_jvm_preview_set_enabled")
public func kk_jvm_preview_set_enabled(_ nameRaw: Int, _ enabledRaw: Int) -> Int {
    guard let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) else {
        return 0
    }
    withPreviewFeatureRegistry {
        if let box = previewFeatureStore[name] {
            box.enabled = enabledRaw != 0
        }
    }
    return 0
}

// MARK: - Java Sealed Class Interop

/// Tracks which concrete subtypes are permitted for a sealed class/interface.
final class RuntimeSealedClassBox {
    private let lock = NSLock()
    let qualifiedName: String
    private var permittedSubclassIDs: [Int64] = []

    init(qualifiedName: String) {
        self.qualifiedName = qualifiedName
    }

    func addPermittedSubclass(typeID: Int64) {
        lock.lock()
        if !permittedSubclassIDs.contains(typeID) {
            permittedSubclassIDs.append(typeID)
        }
        lock.unlock()
    }

    func isPermitted(typeID: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return permittedSubclassIDs.contains(typeID)
    }

    func permittedTypeIDs() -> [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return permittedSubclassIDs
    }
}

private let sealedClassRegistryLock = NSLock()
private nonisolated(unsafe) var sealedClassStore: [Int64: RuntimeSealedClassBox] = [:]

private func withSealedRegistry<T>(_ body: () -> T) -> T {
    sealedClassRegistryLock.lock()
    defer { sealedClassRegistryLock.unlock() }
    return body()
}

@_cdecl("kk_sealed_class_register")
public func kk_sealed_class_register(_ nameRaw: Int) -> Int {
    guard let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)),
          !name.isEmpty
    else {
        return 0
    }
    let typeID = runtimeStableNominalTypeID(fqName: name)
    withSealedRegistry {
        if sealedClassStore[typeID] == nil {
            sealedClassStore[typeID] = RuntimeSealedClassBox(qualifiedName: name)
        }
    }
    return registerRuntimeObject(withSealedRegistry { sealedClassStore[typeID]! })
}

@_cdecl("kk_sealed_class_add_subtype")
public func kk_sealed_class_add_subtype(_ sealedRaw: Int, _ subtypeNameRaw: Int) -> Int {
    guard let sealedPtr = UnsafeMutableRawPointer(bitPattern: sealedRaw),
          let box = tryCast(sealedPtr, to: RuntimeSealedClassBox.self),
          let subtypeName = extractString(from: UnsafeMutableRawPointer(bitPattern: subtypeNameRaw)),
          !subtypeName.isEmpty
    else {
        return 0
    }
    let subtypeID = runtimeStableNominalTypeID(fqName: subtypeName)
    box.addPermittedSubclass(typeID: subtypeID)
    return 0
}

@_cdecl("kk_sealed_class_is_permitted_subtype")
public func kk_sealed_class_is_permitted_subtype(_ sealedRaw: Int, _ subtypeNameRaw: Int) -> Int {
    guard let sealedPtr = UnsafeMutableRawPointer(bitPattern: sealedRaw),
          let box = tryCast(sealedPtr, to: RuntimeSealedClassBox.self),
          let subtypeName = extractString(from: UnsafeMutableRawPointer(bitPattern: subtypeNameRaw)),
          !subtypeName.isEmpty
    else {
        return 0
    }
    let subtypeID = runtimeStableNominalTypeID(fqName: subtypeName)
    return box.isPermitted(typeID: subtypeID) ? 1 : 0
}

// MARK: - Java Records (@JvmRecord)

/// Stores the component values of a Java Record.
final class RuntimeJvmRecordBox {
    let qualifiedName: String
    let componentNames: [String]
    let componentValues: [Int]

    init(qualifiedName: String, componentNames: [String], componentValues: [Int]) {
        self.qualifiedName = qualifiedName
        self.componentNames = componentNames
        self.componentValues = componentValues
    }

    func component(named name: String) -> Int? {
        guard let idx = componentNames.firstIndex(of: name), idx < componentValues.count else {
            return nil
        }
        return componentValues[idx]
    }

    var renderedDescription: String {
        let pairs = zip(componentNames, componentValues)
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: ", ")
        return "\(qualifiedName)[\(pairs)]"
    }
}

@_cdecl("kk_jvm_record_create")
public func kk_jvm_record_create(
    _ nameRaw: Int,
    _ componentNamesRaw: Int,
    _ componentValuesRaw: Int
) -> Int {
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) ?? "<record>"
    guard let namesBox = runtimeArrayBox(from: componentNamesRaw),
          let valuesBox = runtimeArrayBox(from: componentValuesRaw)
    else {
        return registerRuntimeObject(RuntimeJvmRecordBox(
            qualifiedName: name,
            componentNames: [],
            componentValues: []
        ))
    }
    // Build both arrays together via zip so the indices always stay in sync.
    // If extractString fails for a name we drop both the name and its value,
    // avoiding the desynchronisation that a solo compactMap would cause.
    let pairs: [(String, Int)] = zip(namesBox.elements, valuesBox.elements).compactMap { (rawName, rawValue) -> (String, Int)? in
        guard let ptr = UnsafeMutableRawPointer(bitPattern: rawName),
              let name = extractString(from: ptr)
        else { return nil }
        return (name, rawValue)
    }
    let componentNames = pairs.map { $0.0 }
    let componentValues = pairs.map { $0.1 }
    return registerRuntimeObject(RuntimeJvmRecordBox(
        qualifiedName: name,
        componentNames: componentNames,
        componentValues: componentValues
    ))
}

@_cdecl("kk_jvm_record_get_component")
public func kk_jvm_record_get_component(_ recordRaw: Int, _ componentNameRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: recordRaw),
          let box = tryCast(ptr, to: RuntimeJvmRecordBox.self),
          let name = extractString(from: UnsafeMutableRawPointer(bitPattern: componentNameRaw))
    else {
        return runtimeNullSentinelInt
    }
    return box.component(named: name) ?? runtimeNullSentinelInt
}

@_cdecl("kk_jvm_record_to_string")
public func kk_jvm_record_to_string(_ recordRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: recordRaw),
          let box = tryCast(ptr, to: RuntimeJvmRecordBox.self)
    else {
        return registerRuntimeObject(RuntimeStringBox(""))
    }
    return registerRuntimeObject(RuntimeStringBox(box.renderedDescription))
}

@_cdecl("kk_jvm_record_equals")
public func kk_jvm_record_equals(_ aRaw: Int, _ bRaw: Int) -> Int {
    guard let aPtr = UnsafeMutableRawPointer(bitPattern: aRaw),
          let bPtr = UnsafeMutableRawPointer(bitPattern: bRaw),
          let a = tryCast(aPtr, to: RuntimeJvmRecordBox.self),
          let b = tryCast(bPtr, to: RuntimeJvmRecordBox.self)
    else {
        return aRaw == bRaw ? 1 : 0
    }
    guard a.qualifiedName == b.qualifiedName,
          a.componentNames == b.componentNames,
          a.componentValues == b.componentValues
    else {
        return 0
    }
    return 1
}

@_cdecl("kk_jvm_record_hashcode")
public func kk_jvm_record_hashcode(_ recordRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: recordRaw),
          let box = tryCast(ptr, to: RuntimeJvmRecordBox.self)
    else {
        return 0
    }
    var hasher = Hasher()
    hasher.combine(box.qualifiedName)
    for v in box.componentValues {
        hasher.combine(v)
    }
    return hasher.finalize()
}

// MARK: - Pattern Matching for instanceof Interop

/// Performs a type-tag–based instanceof check using the nominal type ID system.
/// Maps directly to `obj instanceof ClassName` in generated JVM bytecode.
@_cdecl("kk_jvm_instanceof")
public func kk_jvm_instanceof(_ objectRaw: Int, _ targetTypeIDRaw: Int) -> Int {
    guard objectRaw != 0, objectRaw != runtimeNullSentinelInt else {
        return 0
    }
    let targetTypeID = Int64(truncatingIfNeeded: targetTypeIDRaw)
    guard let objectTypeID = runtimeObjectTypeID(rawValue: objectRaw) else {
        return 0
    }
    return runtimeIsAssignable(sourceTypeID: objectTypeID, targetTypeID: targetTypeID) ? 1 : 0
}

/// Performs a type-tag–based smart cast binding.
/// Returns the raw value unchanged when the type check succeeds (identity cast);
/// returns runtimeNullSentinelInt on failure.
@_cdecl("kk_jvm_pattern_cast")
public func kk_jvm_pattern_cast(_ objectRaw: Int, _ targetTypeIDRaw: Int) -> Int {
    guard kk_jvm_instanceof(objectRaw, targetTypeIDRaw) != 0 else {
        return runtimeNullSentinelInt
    }
    return objectRaw
}

// MARK: - Switch Expressions (JVM 14+ preview → 16+ stable mapping)

/// Evaluates a dispatch table index for an integer switch expression.
/// `values` is a RuntimeArrayBox of Int sentinels corresponding to case literals.
/// Returns the 0-based index of the matching case, or `defaultIndex` if no match.
@_cdecl("kk_jvm_switch_int")
public func kk_jvm_switch_int(
    _ subjectRaw: Int,
    _ valuesRaw: Int,
    _ defaultIndex: Int
) -> Int {
    guard let valuesBox = runtimeArrayBox(from: valuesRaw) else {
        return defaultIndex
    }
    for (idx, raw) in valuesBox.elements.enumerated() {
        if raw == subjectRaw {
            return idx
        }
    }
    return defaultIndex
}

/// Evaluates a dispatch table index for a String switch expression.
@_cdecl("kk_jvm_switch_string")
public func kk_jvm_switch_string(
    _ subjectRaw: Int,
    _ valuesRaw: Int,
    _ defaultIndex: Int
) -> Int {
    guard let subject = extractString(from: UnsafeMutableRawPointer(bitPattern: subjectRaw)),
          let valuesBox = runtimeArrayBox(from: valuesRaw)
    else {
        return defaultIndex
    }
    for (idx, raw) in valuesBox.elements.enumerated() {
        if let candidate = extractString(from: UnsafeMutableRawPointer(bitPattern: raw)),
           candidate == subject {
            return idx
        }
    }
    return defaultIndex
}

/// Evaluates a dispatch table index for a type-pattern switch expression.
/// `typeIDsRaw` is a RuntimeArrayBox of Int values encoding Int64 type IDs.
@_cdecl("kk_jvm_switch_type_pattern")
public func kk_jvm_switch_type_pattern(
    _ subjectRaw: Int,
    _ typeIDsRaw: Int,
    _ defaultIndex: Int
) -> Int {
    guard subjectRaw != 0, subjectRaw != runtimeNullSentinelInt,
          let typeIDsBox = runtimeArrayBox(from: typeIDsRaw),
          let objectTypeID = runtimeObjectTypeID(rawValue: subjectRaw)
    else {
        return defaultIndex
    }
    for (idx, raw) in typeIDsBox.elements.enumerated() {
        let targetTypeID = Int64(truncatingIfNeeded: raw)
        if runtimeIsAssignable(sourceTypeID: objectTypeID, targetTypeID: targetTypeID) {
            return idx
        }
    }
    return defaultIndex
}

// MARK: - Text Blocks (JVM 15+ preview → 15+ stable)

/// Normalises a raw text-block string literal to its canonical form:
///   1. Strips the mandatory leading newline after the opening `"""`.
///   2. Removes the common leading whitespace prefix from all non-empty lines
///      (re-indent algorithm specified by JEP 378).
///   3. Strips trailing whitespace from each line.
///
/// The compiler lowers `"""…"""` literals and passes the raw content here so
/// that host-platform line-ending differences are handled uniformly.
@_cdecl("kk_jvm_text_block_normalize")
public func kk_jvm_text_block_normalize(_ rawStringRaw: Int) -> Int {
    guard let raw = extractString(from: UnsafeMutableRawPointer(bitPattern: rawStringRaw)) else {
        return registerRuntimeObject(RuntimeStringBox(""))
    }
    let normalized = jvmTextBlockNormalize(raw)
    return registerRuntimeObject(RuntimeStringBox(normalized))
}

/// Pure Swift implementation of JEP 378 text-block normalisation.
func jvmTextBlockNormalize(_ raw: String) -> String {
    // Step 1: strip leading newline (the newline immediately after `"""`)
    var content = raw
    if content.hasPrefix("\r\n") {
        content = String(content.dropFirst(2))
    } else if content.hasPrefix("\n") || content.hasPrefix("\r") {
        content = String(content.dropFirst())
    }

    // Step 2: split into lines (preserve empty lines)
    let lines = content.components(separatedBy: "\n")

    // Step 3: strip trailing whitespace from each line
    let stripped = lines.map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }

    // Step 4: determine common whitespace prefix (ignoring blank lines)
    let nonBlank = stripped.filter { !$0.isEmpty }
    let commonPrefix: String
    if nonBlank.isEmpty {
        commonPrefix = ""
    } else {
        func leadingWhitespace(_ s: String) -> Substring {
            let end = s.firstIndex(where: { $0 != " " && $0 != "\t" }) ?? s.endIndex
            return s[s.startIndex..<end]
        }
        let minIndent = nonBlank.map { leadingWhitespace($0).count }.min() ?? 0
        // Build the common prefix by taking the first `minIndent` characters
        // from the first non-blank line. This preserves the actual whitespace
        // characters (spaces *and* tabs) rather than replacing them all with spaces.
        if minIndent > 0, let first = nonBlank.first {
            commonPrefix = String(leadingWhitespace(first).prefix(minIndent))
        } else {
            commonPrefix = ""
        }
    }

    // Step 5: remove common prefix from each line
    let reindented = stripped.map { line -> String in
        if line.hasPrefix(commonPrefix) {
            return String(line.dropFirst(commonPrefix.count))
        }
        return line
    }

    return reindented.joined(separator: "\n")
}

@_cdecl("kk_jvm_text_block_strip_indent")
public func kk_jvm_text_block_strip_indent(_ rawStringRaw: Int) -> Int {
    guard let raw = extractString(from: UnsafeMutableRawPointer(bitPattern: rawStringRaw)) else {
        return registerRuntimeObject(RuntimeStringBox(""))
    }
    // Alias: full normalise without leading-newline stripping
    let normalized = jvmTextBlockNormalize("\n" + raw)
    return registerRuntimeObject(RuntimeStringBox(normalized))
}

@_cdecl("kk_jvm_text_block_translate_escapes")
public func kk_jvm_text_block_translate_escapes(_ rawStringRaw: Int) -> Int {
    guard let raw = extractString(from: UnsafeMutableRawPointer(bitPattern: rawStringRaw)) else {
        return registerRuntimeObject(RuntimeStringBox(""))
    }
    // Kotlin string literals are already escape-processed by the compiler.
    // This entry point exists for interop completeness; return the value unchanged.
    return registerRuntimeObject(RuntimeStringBox(raw))
}
