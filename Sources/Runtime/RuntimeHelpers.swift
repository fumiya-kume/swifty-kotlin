import Dispatch
import Foundation

func runtimeContinuationState(from continuation: Int) -> RuntimeContinuationState? {
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        return nil
    }
    return Unmanaged<RuntimeContinuationState>.fromOpaque(continuationPtr).takeUnretainedValue()
}

func suspendEntryPoint(from rawValue: Int) -> KKSuspendEntryPoint? {
    guard rawValue != 0 else {
        return nil
    }
    return unsafeBitCast(rawValue, to: KKSuspendEntryPoint.self)
}

func runtimeArrayBox(from rawValue: Int) -> RuntimeArrayBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeArrayBox.self)
}

func runtimeRegisterObjectType(rawValue: Int, classID: Int64) {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue), classID != 0 else {
        return
    }
    runtimeStorage.withLock { state in
        state.objectTypeByPointer[UInt(bitPattern: ptr)] = classID
    }
}

func runtimeObjectTypeID(rawValue: Int) -> Int64? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    return runtimeStorage.withLock { state in
        state.objectTypeByPointer[UInt(bitPattern: ptr)]
    }
}

func runtimeRegisterTypeEdge(childTypeID: Int64, parentTypeID: Int64) {
    guard childTypeID != 0, parentTypeID != 0 else {
        return
    }
    runtimeStorage.withLock { state in
        var parents = state.typeParents[childTypeID] ?? []
        parents.insert(parentTypeID)
        state.typeParents[childTypeID] = parents
    }
}

func runtimeIsAssignable(sourceTypeID: Int64, targetTypeID: Int64) -> Bool {
    guard sourceTypeID != 0, targetTypeID != 0 else {
        return false
    }
    if sourceTypeID == targetTypeID {
        return true
    }
    return runtimeStorage.withLock { state in
        var visited: Set<Int64> = [sourceTypeID]
        var queue: [Int64] = [sourceTypeID]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            if current == targetTypeID {
                return true
            }
            guard let parents = state.typeParents[current] else {
                continue
            }
            for parent in parents where visited.insert(parent).inserted {
                queue.append(parent)
            }
        }
        return false
    }
}

func runtimeAllocateThrowable(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeThrowableBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a CancellationException as a RuntimeCancellationBox (CORO-002 / spec.md J17).
/// The returned opaque pointer can be stored in `outThrown` and later detected via
/// `kk_is_cancellation_exception`.
func runtimeAllocateCancellationException() -> Int {
    let cancellation = RuntimeCancellationBox()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(cancellation).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func tryCast<T: AnyObject>(_ ptr: UnsafeMutableRawPointer, to _: T.Type) -> T? {
    let unmanaged = Unmanaged<AnyObject>.fromOpaque(ptr)
    let anyObject = unmanaged.takeUnretainedValue()
    return anyObject as? T
}

func extractString(from ptr: UnsafeMutableRawPointer?) -> String? {
    guard let ptr = normalizeNullableRuntimePointer(ptr) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    guard let box = tryCast(ptr, to: RuntimeStringBox.self) else {
        return nil
    }
    return box.value
}

let runtimeNullSentinelInt64 = Int64.min
let runtimeNullSentinelInt = Int(truncatingIfNeeded: runtimeNullSentinelInt64)
let runtimeExceptionCaughtSentinel = Int(truncatingIfNeeded: Int64.min + 1)

func normalizeNullableRuntimePointer(_ ptr: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let ptr else {
        return nil
    }
    if UInt(bitPattern: ptr) == UInt(bitPattern: runtimeNullSentinelInt) {
        return nil
    }
    return ptr
}

public final class KKDispatchContinuation: KKContinuation {
    public let context: UnsafeMutableRawPointer?
    private let callback: (UnsafeMutableRawPointer?) -> Void

    public init(context: UnsafeMutableRawPointer?, callback: @escaping (UnsafeMutableRawPointer?) -> Void) {
        self.context = context
        self.callback = callback
    }

    public func resumeWith(_ result: UnsafeMutableRawPointer?) {
        callback(result)
    }
}

public enum KxMiniRuntime {
    public static func runBlocking(_ block: (@escaping (UnsafeMutableRawPointer?) -> Void) -> Void) {
        let group = DispatchGroup()
        group.enter()
        block { _ in group.leave() }
        group.wait()
    }

    public static func launch(_ block: @escaping () -> Void) {
        DispatchQueue.global().async(execute: DispatchWorkItem(block: block))
    }

    public static func async(_ block: @escaping () -> UnsafeMutableRawPointer?) -> KKContinuation {
        KKDispatchContinuation(context: nil) { _ in
            _ = block()
        }
    }

    public static func delay(milliseconds: Int, continuation: KKContinuation) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + .milliseconds(max(0, milliseconds)))
        timer.setEventHandler {
            continuation.resumeWith(nil)
            timer.setEventHandler(handler: nil)
            timer.cancel()
        }
        timer.resume()
    }
}
