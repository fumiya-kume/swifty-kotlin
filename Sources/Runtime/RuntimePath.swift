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
        try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: true)
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

// MARK: - Path.normalize()

/// Purely lexical normalisation matching java.nio.file.Path.normalize():
/// resolves `.` and `..` components without touching the filesystem.
private func lexicalNormalize(_ pathString: String) -> String {
    let isAbsolute = pathString.hasPrefix("/")
    let rawComponents = pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    var stack: [String] = []
    for component in rawComponents {
        if component == "." {
            // skip
        } else if component == ".." {
            if !stack.isEmpty && stack.last != ".." {
                stack.removeLast()
            } else if !isAbsolute {
                stack.append("..")
            }
            // For absolute paths, ".." at root is silently ignored
        } else {
            stack.append(component)
        }
    }
    let joined = stack.joined(separator: "/")
    if isAbsolute {
        return "/" + joined
    } else if joined.isEmpty {
        return ""
    } else {
        return joined
    }
}

@_cdecl("kk_path_normalize")
public func kk_path_normalize(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_normalize received invalid Path handle")
    }
    return registerRuntimeObject(RuntimePathBox(lexicalNormalize(path.pathString)))
}

// MARK: - Path.relativize(other: Path)

@_cdecl("kk_path_relativize")
public func kk_path_relativize(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_relativize received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_relativize received invalid other Path handle")
    }
    // Split into components, stripping leading slash for absolute paths
    let baseComponents = path.pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    let otherComponents = other.pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    // Find common prefix length
    var commonLength = 0
    let minLen = min(baseComponents.count, otherComponents.count)
    while commonLength < minLen && baseComponents[commonLength] == otherComponents[commonLength] {
        commonLength += 1
    }
    // Build relative path: ".." for each remaining base component + remaining other components
    var relComponents: [String] = Array(repeating: "..", count: baseComponents.count - commonLength)
    relComponents += otherComponents[commonLength...]
    let relative = relComponents.isEmpty ? "" : relComponents.joined(separator: "/")
    return registerRuntimeObject(RuntimePathBox(relative))
}

// MARK: - Path.fileName property (returns Path? wrapping the last component, null for root paths)

@_cdecl("kk_path_fileName")
public func kk_path_fileName(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_fileName received invalid Path handle")
    }
    let lastComponent = (path.pathString as NSString).lastPathComponent
    // Root paths (e.g. "/") and empty strings have no file name component
    if lastComponent.isEmpty || lastComponent == "/" {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimePathBox(lastComponent))
}

// MARK: - Path.root property

@_cdecl("kk_path_root")
public func kk_path_root(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_root received invalid Path handle")
    }
    // Only absolute paths have a root ("/")
    guard path.pathString.hasPrefix("/") else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimePathBox("/"))
}

// MARK: - Path.nameCount property

@_cdecl("kk_path_nameCount")
public func kk_path_nameCount(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_nameCount received invalid Path handle")
    }
    let components = path.pathString.split(separator: "/", omittingEmptySubsequences: true)
    return components.count
}

// MARK: - Path.startsWith()

@_cdecl("kk_path_startsWith_path")
public func kk_path_startsWith_path(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith_path received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith_path received invalid other Path handle")
    }
    // Both paths must agree on absolute vs relative; if they disagree, return false.
    let pathIsAbsolute = path.pathString.hasPrefix("/")
    let otherIsAbsolute = other.pathString.hasPrefix("/")
    guard pathIsAbsolute == otherIsAbsolute else { return kk_box_bool(0) }
    let pathComponents = path.pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    let otherComponents = other.pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard otherComponents.count <= pathComponents.count else { return kk_box_bool(0) }
    let result = zip(pathComponents, otherComponents).allSatisfy { $0 == $1 }
    return kk_box_bool(result ? 1 : 0)
}

@_cdecl("kk_path_startsWith_string")
public func kk_path_startsWith_string(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith_string received invalid Path handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let other = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith_string received invalid other string")
    }
    // Both paths must agree on absolute vs relative; if they disagree, return false.
    let pathIsAbsolute = path.pathString.hasPrefix("/")
    let otherIsAbsolute = other.hasPrefix("/")
    guard pathIsAbsolute == otherIsAbsolute else { return kk_box_bool(0) }
    let pathComponents = path.pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    let otherComponents = other.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard otherComponents.count <= pathComponents.count else { return kk_box_bool(0) }
    let result = zip(pathComponents, otherComponents).allSatisfy { $0 == $1 }
    return kk_box_bool(result ? 1 : 0)
}

// MARK: - Path.endsWith()

@_cdecl("kk_path_endsWith_path")
public func kk_path_endsWith_path(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith_path received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith_path received invalid other Path handle")
    }
    // When other is absolute, the entire path must equal `path` exactly (Kotlin semantics).
    let otherIsAbsolute = other.pathString.hasPrefix("/")
    if otherIsAbsolute {
        return kk_box_bool(path.pathString == other.pathString ? 1 : 0)
    }
    let pathComponents = path.pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    let otherComponents = other.pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard otherComponents.count <= pathComponents.count else { return kk_box_bool(0) }
    let result = zip(pathComponents.reversed(), otherComponents.reversed()).allSatisfy { $0 == $1 }
    return kk_box_bool(result ? 1 : 0)
}

@_cdecl("kk_path_endsWith_string")
public func kk_path_endsWith_string(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith_string received invalid Path handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let other = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith_string received invalid other string")
    }
    // When other is absolute, the entire path must equal `path` exactly (Kotlin semantics).
    let otherIsAbsolute = other.hasPrefix("/")
    if otherIsAbsolute {
        return kk_box_bool(path.pathString == other ? 1 : 0)
    }
    let pathComponents = path.pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    let otherComponents = other.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard otherComponents.count <= pathComponents.count else { return kk_box_bool(0) }
    let result = zip(pathComponents.reversed(), otherComponents.reversed()).allSatisfy { $0 == $1 }
    return kk_box_bool(result ? 1 : 0)
}

// MARK: - Path.toFile()

@_cdecl("kk_path_toFile")
public func kk_path_toFile(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toFile received invalid Path handle")
    }
    return registerRuntimeObject(RuntimeFileBox(path.pathString))
}
