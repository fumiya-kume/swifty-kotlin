import Foundation

private struct RuntimeStringBuilderFrame {
    var value = ""
}

private struct RuntimeMutableListFrame {
    var elements: [Int] = []
}

private struct RuntimeMutableMapFrame {
    var keys: [Int] = []
    var values: [Int] = []
}

private struct RuntimeBuilderThreadState {
    var stringFrames: [RuntimeStringBuilderFrame] = []
    var listFrames: [RuntimeMutableListFrame] = []
    var mapFrames: [RuntimeMutableMapFrame] = []

    var isEmpty: Bool {
        stringFrames.isEmpty && listFrames.isEmpty && mapFrames.isEmpty
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

@_cdecl("kk_mutable_list_add")
public func kk_mutable_list_add(_ elem: Int) -> Int {
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

@_cdecl("kk_mutable_map_put")
public func kk_mutable_map_put(_ key: Int, _ value: Int) -> Int {
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
