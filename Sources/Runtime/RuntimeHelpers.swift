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

func runtimeAllocateThrowable(message: String) -> Int {
    let throwable = RuntimeThrowableBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
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
