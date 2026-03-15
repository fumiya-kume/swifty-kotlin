import Foundation

private struct RuntimeStringBuilderFrame {
    var value = ""
}

private struct RuntimeMutableListFrame {
    var elements: [Int] = []
}

private struct RuntimeMutableSetFrame {
    var elements: Set<Int> = []
    var insertionOrder: [Int] = []
}

private struct RuntimeMutableMapFrame {
    var keys: [Int] = []
    var values: [Int] = []
}

private struct RuntimeBuilderThreadState {
    var stringFrames: [RuntimeStringBuilderFrame] = []
    var listFrames: [RuntimeMutableListFrame] = []
    var setFrames: [RuntimeMutableSetFrame] = []
    var mapFrames: [RuntimeMutableMapFrame] = []

    var isEmpty: Bool {
        stringFrames.isEmpty && listFrames.isEmpty && setFrames.isEmpty && mapFrames.isEmpty
    }
}

private final class RuntimeBuilderState: @unchecked Sendable {
    private let lock = NSLock()
    private var threads: [ObjectIdentifier: RuntimeBuilderThreadState] = [:]
    private let maxDepth = 16

    func pushStringFrame() -> Bool {
        withThreadState { state in
            guard state.stringFrames.count < maxDepth else {
                return false
            }
            state.stringFrames.append(RuntimeStringBuilderFrame())
            return true
        }
    }

    func popStringFrame() -> RuntimeStringBuilderFrame? {
        withThreadState { state in
            state.stringFrames.popLast()
        }
    }

    func appendString(_ value: String) {
        withThreadState { state in
            guard !state.stringFrames.isEmpty else {
                return
            }
            state.stringFrames[state.stringFrames.count - 1].value.append(value)
        }
    }

    func insertString(_ value: String, at index: Int) {
        withThreadState { state in
            guard !state.stringFrames.isEmpty else {
                return
            }
            let frameIndex = state.stringFrames.count - 1
            let str = state.stringFrames[frameIndex].value
            let clampedIndex = max(0, min(index, str.count))
            let insertionPoint = str.index(str.startIndex, offsetBy: clampedIndex)
            state.stringFrames[frameIndex].value.insert(contentsOf: value, at: insertionPoint)
        }
    }

    func deleteString(start: Int, end: Int) {
        withThreadState { state in
            guard !state.stringFrames.isEmpty else {
                return
            }
            let frameIndex = state.stringFrames.count - 1
            let str = state.stringFrames[frameIndex].value
            let clampedStart = max(0, min(start, str.count))
            let clampedEnd = max(clampedStart, min(end, str.count))
            let startIdx = str.index(str.startIndex, offsetBy: clampedStart)
            let endIdx = str.index(str.startIndex, offsetBy: clampedEnd)
            state.stringFrames[frameIndex].value.removeSubrange(startIdx..<endIdx)
        }
    }

    func stringLength() -> Int {
        withThreadState { state in
            guard !state.stringFrames.isEmpty else {
                return 0
            }
            return state.stringFrames[state.stringFrames.count - 1].value.count
        }
    }

    func pushListFrame() -> Bool {
        withThreadState { state in
            guard state.listFrames.count < maxDepth else {
                return false
            }
            state.listFrames.append(RuntimeMutableListFrame())
            return true
        }
    }

    func popListFrame() -> RuntimeMutableListFrame? {
        withThreadState { state in
            state.listFrames.popLast()
        }
    }

    func appendListElement(_ value: Int) {
        withThreadState { state in
            guard !state.listFrames.isEmpty else {
                return
            }
            state.listFrames[state.listFrames.count - 1].elements.append(value)
        }
    }

    func pushSetFrame() -> Bool {
        withThreadState { state in
            guard state.setFrames.count < maxDepth else {
                return false
            }
            state.setFrames.append(RuntimeMutableSetFrame())
            return true
        }
    }

    func popSetFrame() -> RuntimeMutableSetFrame? {
        withThreadState { state in
            state.setFrames.popLast()
        }
    }

    func addSetElement(_ value: Int) {
        withThreadState { state in
            guard !state.setFrames.isEmpty else {
                return
            }
            let index = state.setFrames.count - 1
            if state.setFrames[index].elements.insert(value).inserted {
                state.setFrames[index].insertionOrder.append(value)
            }
        }
    }

    func pushMapFrame() -> Bool {
        withThreadState { state in
            guard state.mapFrames.count < maxDepth else {
                return false
            }
            state.mapFrames.append(RuntimeMutableMapFrame())
            return true
        }
    }

    func popMapFrame() -> RuntimeMutableMapFrame? {
        withThreadState { state in
            state.mapFrames.popLast()
        }
    }

    func putMapEntry(key: Int, value: Int) {
        withThreadState { state in
            guard !state.mapFrames.isEmpty else {
                return
            }
            let index = state.mapFrames.count - 1
            if let existing = state.mapFrames[index].keys.firstIndex(of: key) {
                state.mapFrames[index].values[existing] = value
                return
            }
            state.mapFrames[index].keys.append(key)
            state.mapFrames[index].values.append(value)
        }
    }

    private func withThreadState<R>(_ body: (inout RuntimeBuilderThreadState) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        let threadID = ObjectIdentifier(Thread.current)
        var state = threads[threadID] ?? RuntimeBuilderThreadState()
        let result = body(&state)
        if state.isEmpty {
            threads.removeValue(forKey: threadID)
        } else {
            threads[threadID] = state
        }
        return result
    }
}

private let runtimeBuilderState = RuntimeBuilderState()

@_cdecl("kk_string_builder_append")
public func kk_string_builder_append(_ strRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: strRaw),
          let string = extractString(from: pointer)
    else {
        return 0
    }
    runtimeBuilderState.appendString(string)
    return 0
}

@_cdecl("kk_string_builder_appendLine")
public func kk_string_builder_appendLine(_ valueRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: valueRaw),
          let string = extractString(from: pointer)
    else {
        runtimeBuilderState.appendString("\n")
        return 0
    }
    runtimeBuilderState.appendString(string)
    runtimeBuilderState.appendString("\n")
    return 0
}

@_cdecl("kk_string_builder_appendLine_noarg")
public func kk_string_builder_appendLine_noarg() -> Int {
    runtimeBuilderState.appendString("\n")
    return 0
}

@_cdecl("kk_string_builder_insert")
public func kk_string_builder_insert(_ index: Int, _ valueRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: valueRaw),
          let string = extractString(from: pointer)
    else {
        return 0
    }
    runtimeBuilderState.insertString(string, at: index)
    return 0
}

@_cdecl("kk_string_builder_delete")
public func kk_string_builder_delete(_ start: Int, _ end: Int) -> Int {
    runtimeBuilderState.deleteString(start: start, end: end)
    return 0
}

@_cdecl("kk_string_builder_length")
public func kk_string_builder_length() -> Int {
    return runtimeBuilderState.stringLength()
}

@_cdecl("kk_build_string")
public func kk_build_string(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0, runtimeBuilderState.pushStringFrame() else {
        return runtimeMakeStringRaw("")
    }

    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = lambda(&thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }

    let frame = runtimeBuilderState.popStringFrame() ?? RuntimeStringBuilderFrame()
    return runtimeMakeStringRaw(frame.value)
}

@_cdecl("kk_builder_list_add")
public func kk_builder_list_add(_ elem: Int) -> Int {
    runtimeBuilderState.appendListElement(elem)
    return 0
}

@_cdecl("kk_build_list")
public func kk_build_list(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0, runtimeBuilderState.pushListFrame() else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = lambda(&thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }

    let frame = runtimeBuilderState.popListFrame() ?? RuntimeMutableListFrame()
    return registerRuntimeObject(RuntimeListBox(elements: frame.elements))
}

@_cdecl("kk_build_list_with_capacity")
public func kk_build_list_with_capacity(
    _ capacity: Int,
    _ fnPtr: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if capacity < 0 {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: capacity must be non-negative.")
        return 0
    }
    return kk_build_list(fnPtr, outThrown)
}

@_cdecl("kk_builder_set_add")
public func kk_builder_set_add(_ elem: Int) -> Int {
    runtimeBuilderState.addSetElement(elem)
    return 0
}

@_cdecl("kk_build_set")
public func kk_build_set(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0, runtimeBuilderState.pushSetFrame() else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }

    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = lambda(&thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }

    let frame = runtimeBuilderState.popSetFrame() ?? RuntimeMutableSetFrame()
    return registerRuntimeObject(RuntimeSetBox(elements: frame.insertionOrder))
}

@_cdecl("kk_builder_map_put")
public func kk_builder_map_put(_ key: Int, _ value: Int) -> Int {
    runtimeBuilderState.putMapEntry(key: key, value: value)
    return 0
}

@_cdecl("kk_build_map")
public func kk_build_map(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0, runtimeBuilderState.pushMapFrame() else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }

    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = lambda(&thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }

    let frame = runtimeBuilderState.popMapFrame() ?? RuntimeMutableMapFrame()
    return registerRuntimeObject(RuntimeMapBox(keys: frame.keys, values: frame.values))
}

private func runtimeMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cString in
        cString.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}
