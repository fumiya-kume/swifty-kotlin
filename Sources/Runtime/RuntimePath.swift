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

private func pathStringValue(from raw: Int) -> String? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return extractString(from: ptr)
}

private func pathCreateTempDirectoryRaw(
    directoryPath: String,
    prefix: String,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let name = "\(prefix)\(UUID().uuidString)"
    let fullPath = (directoryPath as NSString).appendingPathComponent(name)
    do {
        try FileManager.default.createDirectory(atPath: fullPath, withIntermediateDirectories: false)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return registerRuntimeObject(RuntimePathBox(fullPath))
}

private func pathCreateTempFileRaw(
    directoryPath: String,
    prefix: String,
    suffix: String,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let name = "\(prefix)\(UUID().uuidString)\(suffix)"
    let fullPath = (directoryPath as NSString).appendingPathComponent(name)
    let created = FileManager.default.createFile(atPath: fullPath, contents: nil)
    if !created {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Failed to create temp file \(fullPath)")
    }
    return registerRuntimeObject(RuntimePathBox(fullPath))
}

private func pathLineElements(from raw: Int) -> [Int]? {
    if let list = runtimeListBox(from: raw) {
        return list.elements
    }
    if let array = runtimeArrayBox(from: raw) {
        return array.elements
    }
    return nil
}

private func pathStringEncoding(for charsetRaw: Int) -> String.Encoding {
    switch charsetRaw {
    case 1:
        .isoLatin1
    case 2:
        .ascii
    case 3:
        .utf16
    case 4:
        .utf16BigEndian
    case 5:
        .utf16LittleEndian
    case 6:
        .utf32
    case 7:
        .utf32BigEndian
    case 8:
        .utf32LittleEndian
    default:
        .utf8
    }
}

/// Split a path string into name components, excluding root "/" and empty segments.
private func pathComponents(_ pathString: String) -> [String] {
    pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
}

private enum PathCopyActionResult: Int {
    case continueCopying = 0
    case skipSubtree = 1
    case terminate = 2
}

private enum PathRecursiveCopyControl: Error {
    case terminated
    case thrown(Int)
}

private func pathDefaultCopyAction(sourceURL: URL, targetURL: URL) throws {
    let fileManager = FileManager.default
    var isSourceDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isSourceDirectory) else {
        throw NSError(
            domain: "KSwiftKRuntimePath",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Source path does not exist: \(sourceURL.path)"]
        )
    }

    if isSourceDirectory.boolValue {
        var isTargetDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: targetURL.path, isDirectory: &isTargetDirectory) {
            if isTargetDirectory.boolValue {
                return
            }
            throw NSError(
                domain: "KSwiftKRuntimePath",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Target path already exists: \(targetURL.path)"]
            )
        }
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: false)
    } else {
        if fileManager.fileExists(atPath: targetURL.path) {
            throw NSError(
                domain: "KSwiftKRuntimePath",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Target path already exists: \(targetURL.path)"]
            )
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)
    }
}

private func pathInvokeCopyAction(
    _ copyActionRaw: Int,
    sourceURL: URL,
    targetURL: URL
) throws -> PathCopyActionResult {
    if copyActionRaw == 0 {
        try pathDefaultCopyAction(sourceURL: sourceURL, targetURL: targetURL)
        return .continueCopying
    }

    let sourceRaw = registerRuntimeObject(RuntimePathBox(sourceURL.path))
    let targetRaw = registerRuntimeObject(RuntimePathBox(targetURL.path))
    var thrown = 0
    let resultRaw = kk_function_invoke_3(copyActionRaw, 0, sourceRaw, targetRaw, &thrown)
    if thrown != 0 {
        throw PathRecursiveCopyControl.thrown(thrown)
    }
    return PathCopyActionResult(rawValue: resultRaw) ?? .continueCopying
}

private func pathCopyItemRecursivelyWithAction(
    sourceURL: URL,
    targetURL: URL,
    copyActionRaw: Int
) throws {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
        throw NSError(
            domain: "KSwiftKRuntimePath",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Source path does not exist: \(sourceURL.path)"]
        )
    }

    let actionResult = try pathInvokeCopyAction(copyActionRaw, sourceURL: sourceURL, targetURL: targetURL)
    switch actionResult {
    case .continueCopying:
        break
    case .skipSubtree:
        return
    case .terminate:
        throw PathRecursiveCopyControl.terminated
    }

    guard isDirectory.boolValue else {
        return
    }
    let children = try fileManager.contentsOfDirectory(
        at: sourceURL,
        includingPropertiesForKeys: nil,
        options: []
    )
    for child in children {
        try pathCopyItemRecursivelyWithAction(
            sourceURL: child,
            targetURL: targetURL.appendingPathComponent(child.lastPathComponent),
            copyActionRaw: copyActionRaw
        )
    }
}

private func pathCopyItemRecursively(sourceURL: URL, targetURL: URL, overwrite: Bool) throws {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
        throw NSError(
            domain: "KSwiftKRuntimePath",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Source path does not exist: \(sourceURL.path)"]
        )
    }

    if fileManager.fileExists(atPath: targetURL.path) {
        if overwrite {
            try fileManager.removeItem(at: targetURL)
        } else {
            throw NSError(
                domain: "KSwiftKRuntimePath",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Target path already exists: \(targetURL.path)"]
            )
        }
    }

    if isDirectory.boolValue {
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for child in children {
            try pathCopyItemRecursively(
                sourceURL: child,
                targetURL: targetURL.appendingPathComponent(child.lastPathComponent),
                overwrite: overwrite
            )
        }
    } else {
        try fileManager.copyItem(at: sourceURL, to: targetURL)
    }
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

@_cdecl("kk_path_invariantSeparatorsPath")
public func kk_path_invariantSeparatorsPath(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_invariantSeparatorsPath received invalid Path handle")
    }
    return pathMakeStringRaw(path.pathString.replacingOccurrences(of: "\\", with: "/"))
}

@_cdecl("kk_path_invariantSeparatorsPathString")
public func kk_path_invariantSeparatorsPathString(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_invariantSeparatorsPathString received invalid Path handle")
    }
    return pathMakeStringRaw(path.pathString.replacingOccurrences(of: "\\", with: "/"))
}

@_cdecl("kk_path_pathString")
public func kk_path_pathString(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_pathString received invalid Path handle")
    }
    return pathMakeStringRaw(path.pathString)
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

/// Path.getLastModifiedTime(vararg options: LinkOption): FileTime
///
/// Returns the last modification time of the file system entry referenced by
/// `path` wrapped in a `FileTime` value (milliseconds since the epoch). The
/// `optionsRaw` parameter matches the Sema-declared `vararg options:
/// LinkOption` shape and is accepted for ABI symmetry with the Foundation
/// surface (link options have no effect on the macOS Foundation-backed
/// runtime today). When the underlying `attributesOfItem` call throws, the
/// error is propagated through `outThrown` as an `IOException`, mirroring
/// `kk_files_getLastModifiedTime`'s behaviour.
@_cdecl("kk_path_getLastModifiedTime")
public func kk_path_getLastModifiedTime(_ pathRaw: Int, _ optionsRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_getLastModifiedTime received invalid Path handle")
    }
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.pathString)
        guard let modDate = attrs[.modificationDate] as? Date else {
            return registerRuntimeObject(RuntimeFileTimeBox(milliseconds: 0))
        }
        return registerRuntimeObject(RuntimeFileTimeBox(milliseconds: Int(modDate.timeIntervalSince1970 * 1000)))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeFileTimeBox(milliseconds: 0))
    }
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

@_cdecl("kk_path_appendText_default")
public func kk_path_appendText_default(_ pathRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_path_appendText(pathRaw, textRaw, 0, outThrown)
}

@_cdecl("kk_path_appendText")
public func kk_path_appendText(
    _ pathRaw: Int,
    _ textRaw: Int,
    _ charsetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendText received invalid Path handle")
    }
    guard let text = pathStringValue(from: textRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendText received invalid text")
    }

    let encoding = pathStringEncoding(for: charsetRaw)
    do {
        if FileManager.default.fileExists(atPath: path.pathString) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path.pathString))
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: text.data(using: encoding) ?? Data(text.utf8))
        } else {
            try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

// MARK: - Path.forEachDirectoryEntry

/// Returns true if `name` matches the given glob pattern (filename only, no path separators).
/// Uses POSIX fnmatch semantics.
private func pathGlobMatches(pattern: String, name: String) -> Bool {
    pattern == "*" || fnmatch(pattern, name, 0) == 0
}

/// Invokes the action lambda for every immediate child of `path`, filtered by the
/// optional glob pattern (nil = match all, same as "*").
private func pathForEachDirectoryEntryImpl(
    _ path: RuntimePathBox,
    glob pattern: String?,
    actionRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) {
    outThrown?.pointee = 0
    let entries: [String]
    do {
        entries = try FileManager.default.contentsOfDirectory(atPath: path.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return
    }
    for entry in entries {
        if let pattern, !pathGlobMatches(pattern: pattern, name: entry) {
            continue
        }
        let childPath = (path.pathString as NSString).appendingPathComponent(entry)
        let entryRaw = registerRuntimeObject(RuntimePathBox(childPath))
        var thrown = 0
        _ = kk_function_invoke(actionRaw, entryRaw, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return
        }
    }
}

/// Path.forEachDirectoryEntry(glob: String, action: (Path) -> Unit): Unit
@_cdecl("kk_path_forEachDirectoryEntry")
public func kk_path_forEachDirectoryEntry(
    _ pathRaw: Int,
    _ globRaw: Int,
    _ actionRaw: Int
) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_forEachDirectoryEntry received invalid Path handle")
    }
    let globPattern = pathStringValue(from: globRaw) ?? "*"
    pathForEachDirectoryEntryImpl(path, glob: globPattern, actionRaw: actionRaw, outThrown: nil)
    return 0
}

/// Path.forEachDirectoryEntry(action: (Path) -> Unit): Unit
@_cdecl("kk_path_forEachDirectoryEntry_default")
public func kk_path_forEachDirectoryEntry_default(
    _ pathRaw: Int,
    _ actionRaw: Int
) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_forEachDirectoryEntry_default received invalid Path handle")
    }
    pathForEachDirectoryEntryImpl(path, glob: nil, actionRaw: actionRaw, outThrown: nil)
    return 0
}

@_cdecl("kk_path_copyTo_options")
public func kk_path_copyTo_options(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyTo_options received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyTo_options received invalid target Path handle")
    }
    do {
        try FileManager.default.copyItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_copyTo_overwrite")
public func kk_path_copyTo_overwrite(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyTo_overwrite received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyTo_overwrite received invalid target Path handle")
    }
    do {
        if kk_unbox_bool(overwriteRaw) != 0,
           FileManager.default.fileExists(atPath: target.pathString) {
            try FileManager.default.removeItem(atPath: target.pathString)
        }
        try FileManager.default.copyItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_appendLines_iterable_default")
public func kk_path_appendLines_iterable_default(_ pathRaw: Int, _ linesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_path_appendLines_iterable(pathRaw, linesRaw, 0, outThrown)
}

@_cdecl("kk_path_appendLines_iterable")
public func kk_path_appendLines_iterable(_ pathRaw: Int, _ linesRaw: Int, _ charsetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendLines_iterable received invalid Path handle")
    }
    guard let elements = pathLineElements(from: linesRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendLines_iterable received invalid Iterable handle")
    }
    do {
        let text = elements.map { pathStringValue(from: $0) ?? "null" }.map { $0 + "\n" }.joined()
        let encoding = pathStringEncoding(for: charsetRaw)
        let url = URL(fileURLWithPath: path.pathString)
        if FileManager.default.fileExists(atPath: path.pathString) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = text.data(using: encoding) ?? text.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_appendBytes")
public func kk_path_appendBytes(_ pathRaw: Int, _ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendBytes received invalid Path handle")
    }
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendBytes received invalid ByteArray handle")
    }
    do {
        let url = URL(fileURLWithPath: path.pathString)
        let data = Data(array.elements.map { UInt8(truncatingIfNeeded: $0) })
        if FileManager.default.fileExists(atPath: path.pathString) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
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

/// STDLIB-IO-PATH-FN-020: `Path.forEachLine(charset, action)` extension function.
///
/// Reads the file referenced by `pathRaw` using the encoding implied by
/// `charsetRaw` (mapping defined by `pathStringEncoding`) and invokes
/// `actionRaw` once per logical line, mirroring `kotlin.io.path.forEachLine`.
///
/// Lines follow the same splitting rules as `kk_path_readLines` (the trailing
/// newline does not produce a final empty element) and are passed to the
/// action as boxed Kotlin `String` values. If the action throws, the
/// exception is propagated through `outThrown` and iteration stops.
@_cdecl("kk_path_forEachLine")
public func kk_path_forEachLine(
    _ pathRaw: Int,
    _ charsetRaw: Int,
    _ actionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_forEachLine received invalid Path handle")
    }
    let encoding = pathStringEncoding(for: charsetRaw)
    let content: String
    do {
        content = try String(contentsOfFile: path.pathString, encoding: encoding)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
    for line in pathSplitLines(content) {
        let lineRaw = pathMakeStringRaw(line)
        var thrown = 0
        _ = kk_function_invoke(actionRaw, lineRaw, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return 0
}

/// STDLIB-IO-PATH-FN-020: Default-charset overload of `Path.forEachLine`.
///
/// Mirrors `kotlin.io.path.forEachLine(action)`, which defaults to UTF-8.
@_cdecl("kk_path_forEachLine_default")
public func kk_path_forEachLine_default(
    _ pathRaw: Int,
    _ actionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_path_forEachLine(pathRaw, 0, actionRaw, outThrown)
}

@_cdecl("kk_path_bufferedReader")
public func kk_path_bufferedReader(
    _ pathRaw: Int,
    _ charsetRaw: Int,
    _ bufferSizeRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_bufferedReader received invalid Path handle")
    }
    _ = charsetRaw
    _ = optionsRaw
    let bufferSize = max(1, kk_unbox_int(bufferSizeRaw))
    do {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path.pathString))
        return registerRuntimeObject(RuntimeBufferedReaderBox(fileHandle: fileHandle, chunkSize: bufferSize))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
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

@_cdecl("kk_path_createDirectories_attributes")
public func kk_path_createDirectories_attributes(
    _ pathRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = attributesRaw
    return kk_path_createDirectories(pathRaw, outThrown)
}

@_cdecl("kk_path_createDirectory_attributes")
public func kk_path_createDirectory_attributes(
    _ pathRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createDirectory_attributes received invalid Path handle")
    }
    _ = attributesRaw
    do {
        _ = try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: false)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_createFile_attributes")
public func kk_path_createFile_attributes(
    _ pathRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createFile_attributes received invalid Path handle")
    }
    _ = attributesRaw
    if FileManager.default.fileExists(atPath: path.pathString) {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: file already exists")
        return pathRaw
    }
    let created = FileManager.default.createFile(atPath: path.pathString, contents: Data())
    if !created {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: failed to create file")
    }
    return pathRaw
}

@_cdecl("kk_path_createParentDirectories_attributes")
public func kk_path_createParentDirectories_attributes(
    _ pathRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createParentDirectories_attributes received invalid Path handle")
    }
    _ = attributesRaw
    let parentPath = (path.pathString as NSString).deletingLastPathComponent
    guard !parentPath.isEmpty, parentPath != path.pathString else {
        return pathRaw
    }
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: parentPath, isDirectory: &isDirectory) {
        if !isDirectory.boolValue {
            outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: parent exists and is not a directory")
        }
        return pathRaw
    }
    do {
        _ = try FileManager.default.createDirectory(atPath: parentPath, withIntermediateDirectories: true)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_createSymbolicLinkPointingTo_attributes")
public func kk_path_createSymbolicLinkPointingTo_attributes(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createSymbolicLinkPointingTo_attributes received invalid Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createSymbolicLinkPointingTo_attributes received invalid target Path handle")
    }
    _ = attributesRaw
    do {
        try FileManager.default.createSymbolicLink(atPath: path.pathString, withDestinationPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_createTempDirectory_directory_prefix_attributes")
public func kk_path_createTempDirectory_directory_prefix_attributes(
    _ directoryRaw: Int,
    _ prefixRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = attributesRaw
    let directoryPath = runtimePathBox(from: directoryRaw)?.pathString ?? FileManager.default.temporaryDirectory.path
    let prefix = pathStringValue(from: prefixRaw) ?? "tmp"
    return pathCreateTempDirectoryRaw(
        directoryPath: directoryPath,
        prefix: prefix,
        outThrown: outThrown
    )
}

@_cdecl("kk_path_createTempDirectory_prefix_attributes")
public func kk_path_createTempDirectory_prefix_attributes(
    _ prefixRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = attributesRaw
    let prefix = pathStringValue(from: prefixRaw) ?? "tmp"
    return pathCreateTempDirectoryRaw(
        directoryPath: FileManager.default.temporaryDirectory.path,
        prefix: prefix,
        outThrown: outThrown
    )
}

@_cdecl("kk_path_createTempFile_directory_prefix_suffix_attributes")
public func kk_path_createTempFile_directory_prefix_suffix_attributes(
    _ directoryRaw: Int,
    _ prefixRaw: Int,
    _ suffixRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = attributesRaw
    let directoryPath = runtimePathBox(from: directoryRaw)?.pathString ?? FileManager.default.temporaryDirectory.path
    let prefix = pathStringValue(from: prefixRaw) ?? "tmp"
    let suffix = pathStringValue(from: suffixRaw) ?? ".tmp"
    return pathCreateTempFileRaw(
        directoryPath: directoryPath,
        prefix: prefix,
        suffix: suffix,
        outThrown: outThrown
    )
}

@_cdecl("kk_path_createTempFile_prefix_suffix_attributes")
public func kk_path_createTempFile_prefix_suffix_attributes(
    _ prefixRaw: Int,
    _ suffixRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = attributesRaw
    let prefix = pathStringValue(from: prefixRaw) ?? "tmp"
    let suffix = pathStringValue(from: suffixRaw) ?? ".tmp"
    return pathCreateTempFileRaw(
        directoryPath: FileManager.default.temporaryDirectory.path,
        prefix: prefix,
        suffix: suffix,
        outThrown: outThrown
    )
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

@_cdecl("kk_path_copyToRecursively_overwrite")
public func kk_path_copyToRecursively_overwrite(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ onErrorRaw: Int,
    _ followLinksRaw: Int,
    _ overwriteRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = onErrorRaw
    _ = followLinksRaw
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyToRecursively_overwrite received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyToRecursively_overwrite received invalid target Path handle")
    }

    do {
        try pathCopyItemRecursively(
            sourceURL: URL(fileURLWithPath: source.pathString),
            targetURL: URL(fileURLWithPath: target.pathString),
            overwrite: kk_unbox_bool(overwriteRaw) != 0
        )
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_copyToRecursively_copyAction")
public func kk_path_copyToRecursively_copyAction(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ onErrorRaw: Int,
    _ followLinksRaw: Int,
    _ copyActionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = onErrorRaw
    _ = followLinksRaw
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyToRecursively_copyAction received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyToRecursively_copyAction received invalid target Path handle")
    }

    do {
        try pathCopyItemRecursivelyWithAction(
            sourceURL: URL(fileURLWithPath: source.pathString),
            targetURL: URL(fileURLWithPath: target.pathString),
            copyActionRaw: copyActionRaw
        )
    } catch let control as PathRecursiveCopyControl {
        switch control {
        case .terminated:
            break
        case let .thrown(thrownRaw):
            outThrown?.pointee = thrownRaw
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_moveTo_overwrite")
public func kk_path_moveTo_overwrite(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_moveTo_overwrite received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_moveTo_overwrite received invalid target Path handle")
    }
    do {
        if kk_unbox_bool(overwriteRaw) != 0,
           FileManager.default.fileExists(atPath: target.pathString) {
            try FileManager.default.removeItem(atPath: target.pathString)
        }
        try FileManager.default.moveItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_moveTo_options")
public func kk_path_moveTo_options(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_moveTo_options received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_moveTo_options received invalid target Path handle")
    }
    do {
        try FileManager.default.moveItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
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

// MARK: - Path.useDirectoryEntries(glob, block)

/// Match a file name against a simple glob pattern using POSIX `fnmatch`.
/// Only the last path component (the file name) is matched against `pattern`.
private func pathGlobMatches(pattern: String, name: String) -> Bool {
    pattern.withCString { patternPtr in
        name.withCString { namePtr in
            Darwin.fnmatch(patternPtr, namePtr, 0) == 0
        }
    }
}

/// STDLIB-IO-PATH-FN-037: `Path.useDirectoryEntries(glob, block)` extension function.
///
/// Lists the direct children of the directory at `pathRaw`, filters them
/// by the glob pattern in `globRaw` (defaulting to `"*"` when `globRaw` is 0),
/// wraps them in a `Sequence<Path>` and passes the sequence to the Kotlin lambda
/// in `actionRaw`, mirroring `kotlin.io.path.useDirectoryEntries`.
///
/// The block receives the sequence as its sole argument and may return any type T;
/// the return value is forwarded to the caller.  I/O errors listing the directory
/// cause the block to be invoked with an empty sequence.  Exceptions thrown by the
/// block are NOT propagated (the ABI spec carries no `outThrown` slot).
@_cdecl("kk_path_useDirectoryEntries")
public func kk_path_useDirectoryEntries(
    _ pathRaw: Int,
    _ globRaw: Int,
    _ actionRaw: Int
) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_useDirectoryEntries received invalid Path handle")
    }
    let glob: String
    if globRaw == 0 {
        glob = "*"
    } else {
        glob = pathStringValue(from: globRaw) ?? "*"
    }
    let entries: [String]
    do {
        entries = try FileManager.default.contentsOfDirectory(atPath: path.pathString)
    } catch {
        entries = []
    }
    let elements = entries.compactMap { entry -> Int? in
        guard pathGlobMatches(pattern: glob, name: entry) else { return nil }
        let childPath = (path.pathString as NSString).appendingPathComponent(entry)
        return registerRuntimeObject(RuntimePathBox(childPath))
    }
    let sequenceRaw = registerRuntimeObject(RuntimeListBox(elements: elements))
    var thrown = 0
    let result = kk_function_invoke(actionRaw, sequenceRaw, &thrown)
    return result
}

/// STDLIB-IO-PATH-FN-037: Default-glob overload of `Path.useDirectoryEntries`.
///
/// Mirrors `kotlin.io.path.useDirectoryEntries(block)`, using `"*"` as the glob.
@_cdecl("kk_path_useDirectoryEntries_default")
public func kk_path_useDirectoryEntries_default(
    _ pathRaw: Int,
    _ actionRaw: Int
) -> Int {
    kk_path_useDirectoryEntries(pathRaw, 0, actionRaw)
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

@_cdecl("kk_path_toAbsolutePathString")
public func kk_path_toAbsolutePathString(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toAbsolutePathString received invalid Path handle")
    }
    if path.pathString.hasPrefix("/") {
        return pathMakeStringRaw(path.pathString)
    }
    let absolute = (FileManager.default.currentDirectoryPath as NSString)
        .appendingPathComponent(path.pathString)
    return pathMakeStringRaw(absolute)
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

@_cdecl("kk_path_nameWithoutExtension")
public func kk_path_nameWithoutExtension(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_nameWithoutExtension received invalid Path handle")
    }
    let name = (path.pathString as NSString).lastPathComponent
    guard let dotIndex = name.lastIndex(of: ".") else {
        return pathMakeStringRaw(name)
    }
    return pathMakeStringRaw(String(name[..<dotIndex]))
}

@_cdecl("kk_path_extension")
public func kk_path_extension(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_extension received invalid Path handle")
    }
    let name = (path.pathString as NSString).lastPathComponent
    guard let dotIndex = name.lastIndex(of: ".") else {
        return pathMakeStringRaw("")
    }
    return pathMakeStringRaw(String(name[name.index(after: dotIndex)...]))
}

@_cdecl("kk_path_bufferedWriter")
public func kk_path_bufferedWriter(
    _ pathRaw: Int,
    _ charsetRaw: Int,
    _ bufferSizeRaw: Int,
    _ optionsRaw: Int
) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_bufferedWriter received invalid Path handle")
    }
    _ = optionsRaw
    let url = URL(fileURLWithPath: path.pathString)
    if !FileManager.default.fileExists(atPath: path.pathString) {
        _ = FileManager.default.createFile(atPath: path.pathString, contents: Data())
    }
    do {
        let fileHandle = try FileHandle(forWritingTo: url)
        fileHandle.truncateFile(atOffset: 0)
        let bufferSize = max(1, kk_unbox_int(bufferSizeRaw))
        return registerRuntimeObject(RuntimeBufferedWriterBox(
            fileHandle: fileHandle,
            bufferSize: bufferSize,
            encoding: pathStringEncoding(for: charsetRaw)
        ))
    } catch {
        return 0
    }
}

@_cdecl("kk_path_writer")
public func kk_path_writer(
    _ pathRaw: Int,
    _ charsetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writer received invalid Path handle")
    }
    _ = optionsRaw
    let url = URL(fileURLWithPath: path.pathString)
    if !FileManager.default.fileExists(atPath: path.pathString) {
        _ = FileManager.default.createFile(atPath: path.pathString, contents: Data())
    }
    do {
        let fileHandle = try FileHandle(forWritingTo: url)
        fileHandle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeBufferedWriterBox(
            fileHandle: fileHandle,
            encoding: pathStringEncoding(for: charsetRaw)
        ))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

// MARK: - Path.walk(vararg options: PathWalkOption): Sequence<Path>

/// kotlin.io.path.Path.walk - recursively walks the directory tree starting
/// at `this` path (depth-first, pre-order) and returns a lazy `Sequence<Path>`.
///
/// The root path itself is always the first element of the sequence, matching
/// Kotlin stdlib behavior. The `optionsRaw` parameter accepts the vararg
/// `PathWalkOption` array handle but is not inspected at runtime; all
/// `BREADTH_FIRST` / `FOLLOW_LINKS` variants are silently treated as the
/// default depth-first / no-follow-links walk on macOS.
@_cdecl("kk_path_walk")
public func kk_path_walk(_ pathRaw: Int, _ optionsRaw: Int) -> Int {
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_walk received invalid Path handle")
    }
    var paths: [Int] = [registerRuntimeObject(RuntimePathBox(path.pathString))]
    if let enumerator = FileManager.default.enumerator(atPath: path.pathString) {
        while let relativePath = enumerator.nextObject() as? String {
            let fullPath = (path.pathString as NSString).appendingPathComponent(relativePath)
            paths.append(registerRuntimeObject(RuntimePathBox(fullPath)))
        }
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: paths)]))
}

@_cdecl("kk_path_appendLines_sequence_default")
public func kk_path_appendLines_sequence_default(_ pathRaw: Int, _ linesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_path_appendLines_sequence(pathRaw, linesRaw, 0, outThrown)
}

@_cdecl("kk_path_appendLines_sequence")
public func kk_path_appendLines_sequence(_ pathRaw: Int, _ linesRaw: Int, _ charsetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendLines_sequence received invalid Path handle")
    }
    guard let elements = runtimeSequenceSourceElements(from: linesRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendLines_sequence received invalid lines sequence")
    }
    let text = elements.map { pathStringValue(from: $0) ?? "null" }.map { $0 + "\n" }.joined()
    let encoding = pathStringEncoding(for: charsetRaw)
    do {
        if FileManager.default.fileExists(atPath: path.pathString) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path.pathString))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: text.data(using: encoding) ?? Data(text.utf8))
        } else {
            try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

// MARK: - Path.writeLines()

@_cdecl("kk_path_writeLines_iterable")
public func kk_path_writeLines_iterable(
    _ pathRaw: Int,
    _ linesRaw: Int,
    _ charsetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeLines_iterable received invalid Path handle")
    }
    guard let elements = pathLineElements(from: linesRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeLines_iterable received invalid Iterable handle")
    }
    let text = elements.map { pathStringValue(from: $0) ?? "null" }.map { $0 + "\n" }.joined()
    let encoding = pathStringEncoding(for: charsetRaw)
    do {
        try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_writeLines_sequence")
public func kk_path_writeLines_sequence(
    _ pathRaw: Int,
    _ linesRaw: Int,
    _ charsetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeLines_sequence received invalid Path handle")
    }
    guard let elements = runtimeSequenceSourceElements(from: linesRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeLines_sequence received invalid lines sequence")
    }
    let text = elements.map { pathStringValue(from: $0) ?? "null" }.map { $0 + "\n" }.joined()
    let encoding = pathStringEncoding(for: charsetRaw)
    do {
        try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}
