import Foundation

private final class RuntimeThreadLocalBox {}

private func runtimeThreadLocalBox(from rawValue: Int) -> RuntimeThreadLocalBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isThreadLocalBox = runtimeStorage.withLock { state in
        state.threadLocalBoxes.contains(UInt(bitPattern: ptr))
    }
    guard isThreadLocalBox else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThreadLocalBox.self)
}

private func handleThreadLocalLambdaThrow(_ thrown: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let outThrown {
        outThrown.pointee = thrown
        return runtimeExceptionCaughtSentinel
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Uncaught exception in ThreadLocal.getOrSet lambda. outThrown was nil.")
}

@_cdecl("kk_thread_local_new")
public func kk_thread_local_new() -> Int {
    let box = RuntimeThreadLocalBox()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.threadLocalBoxes.insert(UInt(bitPattern: ptr))
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_thread_local_getOrSet")
public func kk_thread_local_getOrSet(
    _ receiver: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard runtimeThreadLocalBox(from: receiver) != nil else {
        return 0
    }

    let threadKey = ObjectIdentifier(Thread.current)
    let receiverKey = UInt(bitPattern: receiver)

    if let cachedValue = runtimeStorage.withLock({ state -> Int? in
        state.threadLocalValues[receiverKey]?[threadKey]
    }) {
        return cachedValue
    }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 {
        return handleThreadLocalLambdaThrow(thrown, outThrown)
    }
    if result == runtimeNullSentinelInt {
        return result
    }

    runtimeStorage.withLock { state in
        var threadValues = state.threadLocalValues[receiverKey] ?? [:]
        threadValues[threadKey] = result
        state.threadLocalValues[receiverKey] = threadValues
    }
    return result
}
