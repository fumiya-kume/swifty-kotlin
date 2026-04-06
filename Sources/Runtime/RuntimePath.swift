import Foundation

// MARK: - kotlin.io.path.Path Runtime

final class RuntimePathBox {
    let pathString: String
    init(_ pathString: String) { self.pathString = pathString }
}

private func runtimePathBox(from raw: Int) -> RuntimePathBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimePathBox.self)
}

/// Split file content into lines, matching Kotlin behaviour:
/// - Empty string returns an empty array (not `[""]`).
/// - A trailing newline does NOT produce a final empty element.
private func pathSplitLines(_ content: String) -> [String] {
    if content.isEmpty { return [] }
    var lines = content.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

private func pathMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

/// Split a path string into name components, excluding root "/" and empty segments.
private func pathComponents(_ pathString: String) -> [String] {
    pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
}

// MARK: - Path(pathString: String) constructor

@_cdecl("kk_path_new")
public func kk_path_new(_ pathStringRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pathStringRaw),
          let pathString = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_new received invalid pathString")
    }
    return registerRuntimeObject(RuntimePathBox(pathString))
}

// MARK: - Path properties

@_cdecl("kk_path_name")
public func kk_path_name(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_name received invalid Path handle")
    }
    return pathMakeStringRaw((path.pathString as NSString).lastPathComponent)
}

@_cdecl("kk_path_fileName")
public func kk_path_fileName(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_fileName received invalid Path handle")
    }
    let lastComponent = (path.pathString as NSString).lastPathComponent
    if lastComponent.isEmpty || lastComponent == "/" {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimePathBox(lastComponent))
}

@_cdecl("kk_path_parent")
public func kk_path_parent(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_parent received invalid Path handle")
    }
    let parent = (path.pathString as NSString).deletingLastPathComponent
    // Root paths like "/" or "" have no meaningful parent
    if parent.isEmpty || parent == path.pathString {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimePathBox(parent))
}

@_cdecl("kk_path_root")
public func kk_path_root(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_root received invalid Path handle")
    }
    if path.pathString.hasPrefix("/") {
        return registerRuntimeObject(RuntimePathBox("/"))
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_path_nameCount")
public func kk_path_nameCount(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_nameCount received invalid Path handle")
    }
    let components = pathComponents(path.pathString)
    return kk_box_int(components.count)
}

// MARK: - Path.toString()

@_cdecl("kk_path_toString")
public func kk_path_toString(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toString received invalid Path handle")
    }
    return pathMakeStringRaw(path.pathString)
}

// MARK: - Path.resolve()

@_cdecl("kk_path_resolve_string")
public func kk_path_resolve_string(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_resolve_string received invalid Path handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let other = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_resolve_string received invalid other string")
    }
    let resolved = (path.pathString as NSString).appendingPathComponent(other)
    return registerRuntimeObject(RuntimePathBox(resolved))
}

@_cdecl("kk_path_resolve_path")
public func kk_path_resolve_path(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let otherPath = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_resolve_path received invalid other Path handle")
    }
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_resolve_path received invalid Path handle")
    }
    let resolved = (path.pathString as NSString).appendingPathComponent(otherPath.pathString)
    return registerRuntimeObject(RuntimePathBox(resolved))
}

// MARK: - Path query methods

@_cdecl("kk_path_exists")
public func kk_path_exists(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_exists received invalid Path handle")
    }
    return kk_box_bool(FileManager.default.fileExists(atPath: path.pathString) ? 1 : 0)
}

@_cdecl("kk_path_isDirectory")
public func kk_path_isDirectory(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_isDirectory received invalid Path handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path.pathString, isDirectory: &isDir)
    return kk_box_bool(exists && isDir.boolValue ? 1 : 0)
}

@_cdecl("kk_path_isRegularFile")
public func kk_path_isRegularFile(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_isRegularFile received invalid Path handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path.pathString, isDirectory: &isDir)
    return kk_box_bool(exists && !isDir.boolValue ? 1 : 0)
}

// MARK: - Path read/write methods

@_cdecl("kk_path_readText")
public func kk_path_readText(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_readText received invalid Path handle")
    }
    do {
        let content = try String(contentsOfFile: path.pathString, encoding: .utf8)
        return pathMakeStringRaw(content)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return pathMakeStringRaw("")
    }
}

@_cdecl("kk_path_writeText")
public func kk_path_writeText(_ pathRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeText received invalid Path handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeText received invalid text")
    }
    do {
        try text.write(toFile: path.pathString, atomically: true, encoding: .utf8)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_path_readLines")
public func kk_path_readLines(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_readLines received invalid Path handle")
    }
    do {
        let content = try String(contentsOfFile: path.pathString, encoding: .utf8)
        let lines = pathSplitLines(content)
        return registerRuntimeObject(RuntimeListBox(elements: lines.map { pathMakeStringRaw($0) }))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

// MARK: - Path filesystem operations

@_cdecl("kk_path_createDirectories")
public func kk_path_createDirectories(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createDirectories received invalid Path handle")
    }
    do {
        _ = try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: true)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    // Returns the Path itself (this)
    return pathRaw
}

@_cdecl("kk_path_deleteIfExists")
public func kk_path_deleteIfExists(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_deleteIfExists received invalid Path handle")
    }
    guard FileManager.default.fileExists(atPath: path.pathString) else {
        return kk_box_bool(0)
    }
    return kk_box_bool((try? FileManager.default.removeItem(atPath: path.pathString)) != nil ? 1 : 0)
}

@_cdecl("kk_path_listDirectoryEntries")
public func kk_path_listDirectoryEntries(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_listDirectoryEntries received invalid Path handle")
    }
    do {
        let entries = try FileManager.default.contentsOfDirectory(atPath: path.pathString)
        let elements = entries.map { entry -> Int in
            let childPath = (path.pathString as NSString).appendingPathComponent(entry)
            return registerRuntimeObject(RuntimePathBox(childPath))
        }
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

// MARK: - Path.relativize(other: Path)

@_cdecl("kk_path_relativize")
public func kk_path_relativize(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let base = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_relativize received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_relativize received invalid other Path handle")
    }
    let baseComponents = pathComponents(base.pathString)
    let otherComponents = pathComponents(other.pathString)

    var commonLength = 0
    while commonLength < baseComponents.count && commonLength < otherComponents.count
        && baseComponents[commonLength] == otherComponents[commonLength] {
        commonLength += 1
    }

    let ups = Array(repeating: "..", count: baseComponents.count - commonLength)
    let remainder = Array(otherComponents[commonLength...])
    let relativePath = (ups + remainder).joined(separator: "/")
    return registerRuntimeObject(RuntimePathBox(relativePath.isEmpty ? "." : relativePath))
}

// MARK: - Path.normalize()

@_cdecl("kk_path_normalize")
public func kk_path_normalize(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_normalize received invalid Path handle")
    }
    let isAbsolute = path.pathString.hasPrefix("/")
    var components: [String] = []
    for part in path.pathString.split(separator: "/", omittingEmptySubsequences: true) {
        let s = String(part)
        if s == "." {
            continue
        } else if s == ".." {
            if !components.isEmpty && components.last != ".." {
                components.removeLast()
            } else if !isAbsolute {
                components.append(s)
            }
        } else {
            components.append(s)
        }
    }
    let normalized = (isAbsolute ? "/" : "") + components.joined(separator: "/")
    return registerRuntimeObject(RuntimePathBox(normalized.isEmpty ? "." : normalized))
}

// MARK: - Path comparison methods

@_cdecl("kk_path_equals")
public func kk_path_equals(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_equals received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(path.pathString == other.pathString ? 1 : 0)
}

@_cdecl("kk_path_startsWith_path")
public func kk_path_startsWith_path(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith received invalid other Path handle")
    }
    let pathParts = pathComponents(path.pathString)
    let otherParts = pathComponents(other.pathString)
    let pathIsAbsolute = path.pathString.hasPrefix("/")
    let otherIsAbsolute = other.pathString.hasPrefix("/")
    guard pathIsAbsolute == otherIsAbsolute, otherParts.count <= pathParts.count else {
        return kk_box_bool(0)
    }
    for i in 0..<otherParts.count {
        if pathParts[i] != otherParts[i] { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}

@_cdecl("kk_path_startsWith_string")
public func kk_path_startsWith_string(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let otherStr = extractString(from: ptr) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith_string received invalid string")
    }
    let otherPath = registerRuntimeObject(RuntimePathBox(otherStr))
    return kk_path_startsWith_path(pathRaw, otherPath)
}

@_cdecl("kk_path_endsWith_path")
public func kk_path_endsWith_path(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith received invalid other Path handle")
    }
    let pathParts = pathComponents(path.pathString)
    let otherParts = pathComponents(other.pathString)
    // If other is absolute, it must match from root
    if other.pathString.hasPrefix("/") {
        guard path.pathString.hasPrefix("/"), otherParts.count <= pathParts.count else {
            return kk_box_bool(0)
        }
        for i in 0..<otherParts.count {
            if pathParts[i] != otherParts[i] { return kk_box_bool(0) }
        }
        return kk_box_bool(1)
    }
    guard otherParts.count <= pathParts.count else {
        return kk_box_bool(0)
    }
    let offset = pathParts.count - otherParts.count
    for i in 0..<otherParts.count {
        if pathParts[offset + i] != otherParts[i] { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}

@_cdecl("kk_path_endsWith_string")
public func kk_path_endsWith_string(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let otherStr = extractString(from: ptr) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith_string received invalid string")
    }
    let otherPath = registerRuntimeObject(RuntimePathBox(otherStr))
    return kk_path_endsWith_path(pathRaw, otherPath)
}

// MARK: - Path conversion methods

@_cdecl("kk_path_toFile")
public func kk_path_toFile(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toFile received invalid Path handle")
    }
    return registerRuntimeObject(RuntimeFileBox(path.pathString))
}

@_cdecl("kk_path_toUri")
public func kk_path_toUri(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toUri received invalid Path handle")
    }
    let absolutePath: String
    if path.pathString.hasPrefix("/") {
        absolutePath = path.pathString
    } else {
        absolutePath = (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent(path.pathString)
    }
    let uriString = "file://" + absolutePath
    if var components = URLComponents(string: uriString) {
        components.scheme = "file"
        return registerRuntimeObject(RuntimeURIBox(components: components))
    }
    // Fallback: create from raw string
    var fallback = URLComponents()
    fallback.scheme = "file"
    fallback.path = absolutePath
    return registerRuntimeObject(RuntimeURIBox(components: fallback))
}

// MARK: - Path.get() / Paths.get() top-level factory

@_cdecl("kk_path_get")
public func kk_path_get(_ pathStringRaw: Int) -> Int {
    return kk_path_new(pathStringRaw)
}

@_cdecl("kk_path_isAbsolute")
public func kk_path_isAbsolute(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_isAbsolute received invalid Path handle")
    }
    return kk_box_bool(path.pathString.hasPrefix("/") ? 1 : 0)
}

@_cdecl("kk_path_toAbsolutePath")
public func kk_path_toAbsolutePath(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toAbsolutePath received invalid Path handle")
    }
    if path.pathString.hasPrefix("/") {
        return pathRaw
    }
    let absolute = (FileManager.default.currentDirectoryPath as NSString)
        .appendingPathComponent(path.pathString)
    return registerRuntimeObject(RuntimePathBox(absolute))
}

@_cdecl("kk_path_getName")
public func kk_path_getName(_ pathRaw: Int, _ indexRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_getName received invalid Path handle")
    }
    let index = kk_unbox_int(indexRaw)
    let components = pathComponents(path.pathString)
    guard index >= 0 && index < components.count else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_getName index out of bounds: \(index)")
    }
    return registerRuntimeObject(RuntimePathBox(components[index]))
}
