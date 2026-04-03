import Foundation

struct RuntimeKAPTGeneratedFileRecord: Equatable {
    let path: String
    let originatingSource: String?
}

struct RuntimeKAPTDiagnosticRecord: Equatable {
    let message: String
    let sourcePath: String?
    let line: Int
    let column: Int

    var rendered: String {
        var prefix = sourcePath ?? "<unknown>"
        if line > 0 {
            prefix += ":\(line)"
            if column > 0 {
                prefix += ":\(column)"
            }
        }
        return "\(prefix): error: \(message)"
    }
}

private final class RuntimeKAPTRoundState {
    let number: Int
    let annotations: [String]
    let sourcePaths: [String]
    let incomingGeneratedFiles: [RuntimeKAPTGeneratedFileRecord]
    var outgoingGeneratedFiles: [RuntimeKAPTGeneratedFileRecord] = []

    init(
        number: Int,
        annotations: [String],
        sourcePaths: [String],
        incomingGeneratedFiles: [RuntimeKAPTGeneratedFileRecord]
    ) {
        self.number = number
        self.annotations = annotations
        self.sourcePaths = sourcePaths
        self.incomingGeneratedFiles = incomingGeneratedFiles
    }
}

final class RuntimeKAPTRoundBox {
    let number: Int
    let processingOver: Bool
    let annotations: [String]
    let sourcePaths: [String]
    let incomingGeneratedFiles: [RuntimeKAPTGeneratedFileRecord]

    init(
        number: Int,
        processingOver: Bool,
        annotations: [String],
        sourcePaths: [String],
        incomingGeneratedFiles: [RuntimeKAPTGeneratedFileRecord]
    ) {
        self.number = number
        self.processingOver = processingOver
        self.annotations = annotations
        self.sourcePaths = sourcePaths
        self.incomingGeneratedFiles = incomingGeneratedFiles
    }
}

final class RuntimeKAPTSessionBox {
    private let lock = NSLock()

    private let incrementalEnabled: Bool
    private var options: [String: String]
    private var knownSourcePaths: Set<String> = []
    private var annotationsBySource: [String: Set<String>] = [:]
    private var dirtySourcePaths: Set<String> = []
    private var queuedGeneratedFiles: [RuntimeKAPTGeneratedFileRecord] = []
    private var allGeneratedFiles: [RuntimeKAPTGeneratedFileRecord] = []
    private var diagnostics: [RuntimeKAPTDiagnosticRecord] = []
    private var roundNumber = 0
    private var activeRound: RuntimeKAPTRoundState?

    init(incrementalEnabled: Bool, options: [String: String] = [:]) {
        self.incrementalEnabled = incrementalEnabled
        self.options = options
    }

    func addOption(key: String, value: String) {
        lock.lock()
        options[key] = value
        lock.unlock()
    }

    func optionValue(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return options[key]
    }

    func optionKeys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return options.keys.sorted()
    }

    func registerAnnotatedSource(path: String, annotation: String) {
        lock.lock()
        knownSourcePaths.insert(path)
        annotationsBySource[path, default: []].insert(annotation)
        lock.unlock()
    }

    func markDirty(path: String) {
        lock.lock()
        knownSourcePaths.insert(path)
        dirtySourcePaths.insert(path)
        lock.unlock()
    }

    func dirtySourceCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return dirtySourcePaths.count
    }

    func shouldProcess(path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !incrementalEnabled {
            return true
        }
        return dirtySourcePaths.contains(path) || queuedGeneratedFiles.contains(where: { $0.path == path })
    }

    func beginRound() -> RuntimeKAPTRoundBox {
        lock.lock()
        defer { lock.unlock() }

        let incomingGeneratedFiles = queuedGeneratedFiles
        queuedGeneratedFiles = []

        let selectedSources: [String]
        if incrementalEnabled {
            let incrementalSources = dirtySourcePaths.union(incomingGeneratedFiles.map(\.path))
            if roundNumber == 0, incrementalSources.isEmpty {
                selectedSources = knownSourcePaths.sorted()
            } else {
                selectedSources = incrementalSources.sorted()
            }
        } else {
            selectedSources = knownSourcePaths.union(incomingGeneratedFiles.map(\.path)).sorted()
        }

        let annotationNames = selectedSources
            .flatMap { annotationsBySource[$0] ?? [] }
        let uniqueAnnotations = Array(Set(annotationNames)).sorted()
        let processingOver = selectedSources.isEmpty && incomingGeneratedFiles.isEmpty

        roundNumber += 1
        let state = RuntimeKAPTRoundState(
            number: roundNumber,
            annotations: uniqueAnnotations,
            sourcePaths: selectedSources,
            incomingGeneratedFiles: incomingGeneratedFiles
        )
        activeRound = state
        return RuntimeKAPTRoundBox(
            number: state.number,
            processingOver: processingOver,
            annotations: state.annotations,
            sourcePaths: state.sourcePaths,
            incomingGeneratedFiles: state.incomingGeneratedFiles
        )
    }

    func emitGeneratedFile(path: String, originatingSource: String?) {
        lock.lock()
        defer { lock.unlock() }

        let record = RuntimeKAPTGeneratedFileRecord(path: path, originatingSource: originatingSource)
        if !allGeneratedFiles.contains(record) {
            allGeneratedFiles.append(record)
        }
        knownSourcePaths.insert(path)
        activeRound?.outgoingGeneratedFiles.append(record)
        if incrementalEnabled {
            dirtySourcePaths.insert(path)
        }
    }

    func finishRound() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let activeRound else {
            return false
        }

        queuedGeneratedFiles = activeRound.outgoingGeneratedFiles
        self.activeRound = nil

        if queuedGeneratedFiles.isEmpty {
            dirtySourcePaths.removeAll()
            return false
        }

        return true
    }

    func generatedFiles() -> [RuntimeKAPTGeneratedFileRecord] {
        lock.lock()
        defer { lock.unlock() }
        return allGeneratedFiles
    }

    func reportError(message: String, sourcePath: String?, line: Int, column: Int) {
        lock.lock()
        diagnostics.append(
            RuntimeKAPTDiagnosticRecord(
                message: message,
                sourcePath: sourcePath,
                line: line,
                column: column
            )
        )
        lock.unlock()
    }

    func hasErrors() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !diagnostics.isEmpty
    }

    func renderedErrors() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return diagnostics.map(\.rendered)
    }
}

private func runtimeKAPTSessionBox(from raw: Int) -> RuntimeKAPTSessionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKAPTSessionBox.self)
}

private func runtimeKAPTRoundBox(from raw: Int) -> RuntimeKAPTRoundBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKAPTRoundBox.self)
}

private func runtimeKAPTString(_ value: String) -> Int {
    let utf8 = Array(value.utf8)
    if utf8.isEmpty {
        var emptyByte: UInt8 = 0
        return withUnsafePointer(to: &emptyByte) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, 0))
        }
    }
    return utf8.withUnsafeBufferPointer { buffer in
        Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
    }
}

private func runtimeKAPTStringList(_ values: [String]) -> Int {
    let raws = values.map(runtimeKAPTString)
    return registerRuntimeObject(RuntimeListBox(elements: raws))
}

private func runtimeKAPTGeneratedFileList(_ values: [RuntimeKAPTGeneratedFileRecord]) -> Int {
    let rendered = values.map { record in
        if let originatingSource = record.originatingSource, !originatingSource.isEmpty {
            return "\(record.path)|\(originatingSource)"
        }
        return record.path
    }
    return runtimeKAPTStringList(rendered)
}

@_cdecl("kk_kapt_session_create")
public func kk_kapt_session_create(_ incrementalEnabled: Int) -> Int {
    registerRuntimeObject(RuntimeKAPTSessionBox(incrementalEnabled: incrementalEnabled != 0))
}

@_cdecl("kk_kapt_session_add_option")
public func kk_kapt_session_add_option(_ sessionRaw: Int, _ keyRaw: Int, _ valueRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KAPT session handle")
    }
    let key = extractString(from: UnsafeMutableRawPointer(bitPattern: keyRaw)) ?? ""
    let value = extractString(from: UnsafeMutableRawPointer(bitPattern: valueRaw)) ?? ""
    guard !key.isEmpty else {
        return 0
    }
    session.addOption(key: key, value: value)
    return 0
}

@_cdecl("kk_kapt_session_get_option")
public func kk_kapt_session_get_option(_ sessionRaw: Int, _ keyRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        return runtimeNullSentinelInt
    }
    let key = extractString(from: UnsafeMutableRawPointer(bitPattern: keyRaw)) ?? ""
    guard let value = session.optionValue(for: key) else {
        return runtimeNullSentinelInt
    }
    return runtimeKAPTString(value)
}

@_cdecl("kk_kapt_session_get_option_keys")
public func kk_kapt_session_get_option_keys(_ sessionRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKAPTStringList(session.optionKeys())
}

@_cdecl("kk_kapt_session_register_annotation")
public func kk_kapt_session_register_annotation(_ sessionRaw: Int, _ sourcePathRaw: Int, _ annotationRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KAPT session handle")
    }
    guard let sourcePath = extractString(from: UnsafeMutableRawPointer(bitPattern: sourcePathRaw)),
          let annotation = extractString(from: UnsafeMutableRawPointer(bitPattern: annotationRaw)),
          !sourcePath.isEmpty,
          !annotation.isEmpty
    else {
        return 0
    }
    session.registerAnnotatedSource(path: sourcePath, annotation: annotation)
    return 0
}

@_cdecl("kk_kapt_session_mark_dirty")
public func kk_kapt_session_mark_dirty(_ sessionRaw: Int, _ sourcePathRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KAPT session handle")
    }
    guard let sourcePath = extractString(from: UnsafeMutableRawPointer(bitPattern: sourcePathRaw)),
          !sourcePath.isEmpty
    else {
        return 0
    }
    session.markDirty(path: sourcePath)
    return 0
}

@_cdecl("kk_kapt_session_dirty_source_count")
public func kk_kapt_session_dirty_source_count(_ sessionRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        return 0
    }
    return session.dirtySourceCount()
}

@_cdecl("kk_kapt_session_should_process")
public func kk_kapt_session_should_process(_ sessionRaw: Int, _ sourcePathRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw),
          let sourcePath = extractString(from: UnsafeMutableRawPointer(bitPattern: sourcePathRaw)),
          !sourcePath.isEmpty
    else {
        return 0
    }
    return session.shouldProcess(path: sourcePath) ? 1 : 0
}

@_cdecl("kk_kapt_session_begin_round")
public func kk_kapt_session_begin_round(_ sessionRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KAPT session handle")
    }
    return registerRuntimeObject(session.beginRound())
}

@_cdecl("kk_kapt_round_get_number")
public func kk_kapt_round_get_number(_ roundRaw: Int) -> Int {
    runtimeKAPTRoundBox(from: roundRaw)?.number ?? 0
}

@_cdecl("kk_kapt_round_is_processing_over")
public func kk_kapt_round_is_processing_over(_ roundRaw: Int) -> Int {
    (runtimeKAPTRoundBox(from: roundRaw)?.processingOver ?? true) ? 1 : 0
}

@_cdecl("kk_kapt_round_get_annotations")
public func kk_kapt_round_get_annotations(_ roundRaw: Int) -> Int {
    guard let round = runtimeKAPTRoundBox(from: roundRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKAPTStringList(round.annotations)
}

@_cdecl("kk_kapt_round_get_sources")
public func kk_kapt_round_get_sources(_ roundRaw: Int) -> Int {
    guard let round = runtimeKAPTRoundBox(from: roundRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKAPTStringList(round.sourcePaths)
}

@_cdecl("kk_kapt_round_get_incoming_generated_files")
public func kk_kapt_round_get_incoming_generated_files(_ roundRaw: Int) -> Int {
    guard let round = runtimeKAPTRoundBox(from: roundRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKAPTGeneratedFileList(round.incomingGeneratedFiles)
}

@_cdecl("kk_kapt_session_emit_generated_file")
public func kk_kapt_session_emit_generated_file(_ sessionRaw: Int, _ pathRaw: Int, _ originatingSourceRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KAPT session handle")
    }
    guard let path = extractString(from: UnsafeMutableRawPointer(bitPattern: pathRaw)),
          !path.isEmpty
    else {
        return 0
    }
    let originatingSource = extractString(from: UnsafeMutableRawPointer(bitPattern: originatingSourceRaw))
    session.emitGeneratedFile(path: path, originatingSource: originatingSource)
    return 0
}

@_cdecl("kk_kapt_session_finish_round")
public func kk_kapt_session_finish_round(_ sessionRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        return 0
    }
    return session.finishRound() ? 1 : 0
}

@_cdecl("kk_kapt_session_get_generated_files")
public func kk_kapt_session_get_generated_files(_ sessionRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKAPTGeneratedFileList(session.generatedFiles())
}

@_cdecl("kk_kapt_session_report_error")
public func kk_kapt_session_report_error(
    _ sessionRaw: Int,
    _ messageRaw: Int,
    _ sourcePathRaw: Int,
    _ line: Int,
    _ column: Int
) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KAPT session handle")
    }
    let message = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw)) ?? "annotation processing failed"
    let sourcePath = extractString(from: UnsafeMutableRawPointer(bitPattern: sourcePathRaw))
    session.reportError(message: message, sourcePath: sourcePath, line: line, column: column)
    return 0
}

@_cdecl("kk_kapt_session_has_errors")
public func kk_kapt_session_has_errors(_ sessionRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        return 0
    }
    return session.hasErrors() ? 1 : 0
}

@_cdecl("kk_kapt_session_get_errors")
public func kk_kapt_session_get_errors(_ sessionRaw: Int) -> Int {
    guard let session = runtimeKAPTSessionBox(from: sessionRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeKAPTStringList(session.renderedErrors())
}
