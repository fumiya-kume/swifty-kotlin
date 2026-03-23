import Foundation

// MARK: - File I/O Runtime (STDLIB-320/321/322/323)

final class RuntimeFileBox {
    let path: String
    init(_ path: String) { self.path = path }
}

private func runtimeFileBox(from raw: Int) -> RuntimeFileBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileBox.self)
}

/// Split file content into lines, matching Kotlin behaviour:
/// - Empty string returns an empty array (not `[""]`).
/// - A trailing newline does NOT produce a final empty element.
private func fileSplitLines(_ content: String) -> [String] {
    if content.isEmpty { return [] }
    var lines = content.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

private func fileMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

// MARK: - STDLIB-320: File constructor and basic operations

@_cdecl("kk_file_new")
public func kk_file_new(_ pathRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pathRaw),
          let path = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_new received invalid path")
    }
    return registerRuntimeObject(RuntimeFileBox(path))
}

@_cdecl("kk_file_readText")
public func kk_file_readText(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_readText received invalid File handle")
    }
    do {
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        return fileMakeStringRaw(content)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return fileMakeStringRaw("")
    }
}

@_cdecl("kk_file_writeText")
public func kk_file_writeText(_ fileRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_writeText received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_writeText received invalid text")
    }
    do {
        try text.write(toFile: file.path, atomically: true, encoding: .utf8)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_file_appendText")
public func kk_file_appendText(_ fileRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_appendText received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_appendText received invalid text")
    }
    do {
        let url = URL(fileURLWithPath: file.path)
        if FileManager.default.fileExists(atPath: file.path) {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            if let data = text.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try text.write(toFile: file.path, atomically: true, encoding: .utf8)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_file_readLines")
public func kk_file_readLines(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_readLines received invalid File handle")
    }
    do {
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        let lines = fileSplitLines(content)
        return registerRuntimeObject(RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) }))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

// MARK: - STDLIB-665: File.readBytes()

@_cdecl("kk_file_readBytes")
public func kk_file_readBytes(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_readBytes received invalid File handle")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: file.path))
        let elements = data.map { Int(Int8(bitPattern: $0)) }
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

// MARK: - STDLIB-321: File properties and existence checks

@_cdecl("kk_file_exists")
public func kk_file_exists(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_exists received invalid File handle")
    }
    return kk_box_bool(FileManager.default.fileExists(atPath: file.path) ? 1 : 0)
}

@_cdecl("kk_file_isFile")
public func kk_file_isFile(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_isFile received invalid File handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
    return kk_box_bool(exists && !isDir.boolValue ? 1 : 0)
}

@_cdecl("kk_file_isDirectory")
public func kk_file_isDirectory(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_isDirectory received invalid File handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
    return kk_box_bool(exists && isDir.boolValue ? 1 : 0)
}

@_cdecl("kk_file_name")
public func kk_file_name(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_name received invalid File handle")
    }
    return fileMakeStringRaw((file.path as NSString).lastPathComponent)
}

@_cdecl("kk_file_path")
public func kk_file_path(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_path received invalid File handle")
    }
    return fileMakeStringRaw(file.path)
}

// MARK: - STDLIB-322: File line-by-line operations

@_cdecl("kk_file_forEachLine")
public func kk_file_forEachLine(_ fileRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_forEachLine received invalid File handle")
    }
    guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Cannot read file \(file.path)")
        return 0
    }
    let lines = fileSplitLines(content)
    for line in lines {
        let lineRaw = fileMakeStringRaw(line)
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: lineRaw, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return 0
}

// MARK: - STDLIB-566: File.useLines {}

@_cdecl("kk_file_useLines")
public func kk_file_useLines(_ fileRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_useLines received invalid File handle")
    }
    guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Cannot read file \(file.path)")
        return 0
    }
    let lines = fileSplitLines(content)
    let linesList = RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) })
    let linesListRaw = registerRuntimeObject(linesList)
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: linesListRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

// MARK: - STDLIB-323: File filesystem operations

@_cdecl("kk_file_delete")
public func kk_file_delete(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_delete received invalid File handle")
    }
    return kk_box_bool((try? FileManager.default.removeItem(atPath: file.path)) != nil ? 1 : 0)
}

@_cdecl("kk_file_mkdirs")
public func kk_file_mkdirs(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_mkdirs received invalid File handle")
    }
    return kk_box_bool((try? FileManager.default.createDirectory(atPath: file.path, withIntermediateDirectories: true)) != nil ? 1 : 0)
}

@_cdecl("kk_file_listFiles")
public func kk_file_listFiles(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_listFiles received invalid File handle")
    }
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: file.path) else {
        return runtimeNullSentinelInt
    }
    let elements = entries.map { entry -> Int in
        let childPath = (file.path as NSString).appendingPathComponent(entry)
        return registerRuntimeObject(RuntimeFileBox(childPath))
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_file_walk")
public func kk_file_walk(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_walk received invalid File handle")
    }
    // Kotlin's File.walk() includes the root directory itself as the first element
    var files: [Int] = [registerRuntimeObject(RuntimeFileBox(file.path))]
    if let enumerator = FileManager.default.enumerator(atPath: file.path) {
        while let relativePath = enumerator.nextObject() as? String {
            let fullPath = (file.path as NSString).appendingPathComponent(relativePath)
            files.append(registerRuntimeObject(RuntimeFileBox(fullPath)))
        }
    }
    // Return as a Sequence (list of File handles)
    let listBox = RuntimeListBox(elements: files)
    return registerRuntimeObject(listBox)
}

// MARK: - STDLIB-567: File.bufferedReader()

private func runtimeBufferedReaderBox(from raw: Int) -> RuntimeBufferedReaderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedReaderBox.self)
}

@_cdecl("kk_file_bufferedReader")
public func kk_file_bufferedReader(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_bufferedReader received invalid File handle")
    }
    do {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: file.path))
        return registerRuntimeObject(RuntimeBufferedReaderBox(fileHandle: fileHandle))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

@_cdecl("kk_buffered_reader_readLine")
public func kk_buffered_reader_readLine(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_readLine received invalid BufferedReader handle")
    }
    guard let line = reader.readLine() else {
        return runtimeNullSentinelInt
    }
    return fileMakeStringRaw(line)
}

@_cdecl("kk_buffered_reader_readLines")
public func kk_buffered_reader_readLines(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_readLines received invalid BufferedReader handle")
    }
    let lines = reader.readLines()
    return registerRuntimeObject(RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) }))
}

@_cdecl("kk_buffered_reader_close")
public func kk_buffered_reader_close(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_close received invalid BufferedReader handle")
    }
    reader.close()
    return 0
}
