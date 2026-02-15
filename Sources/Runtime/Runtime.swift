import Foundation
import Dispatch

public struct KTypeInfo {
    public let fqName: UnsafePointer<CChar>
    public let instanceSize: UInt32
    public let fieldCount: UInt32
    public let fieldOffsets: UnsafePointer<UInt32>
    public let vtableSize: UInt32
    public let vtable: UnsafePointer<UnsafeRawPointer>
    public let itable: UnsafeRawPointer?
    public let gcDescriptor: UnsafeRawPointer?

    public init(
        fqName: UnsafePointer<CChar>,
        instanceSize: UInt32,
        fieldCount: UInt32,
        fieldOffsets: UnsafePointer<UInt32>,
        vtableSize: UInt32,
        vtable: UnsafePointer<UnsafeRawPointer>,
        itable: UnsafeRawPointer?,
        gcDescriptor: UnsafeRawPointer?
    ) {
        self.fqName = fqName
        self.instanceSize = instanceSize
        self.fieldCount = fieldCount
        self.fieldOffsets = fieldOffsets
        self.vtableSize = vtableSize
        self.vtable = vtable
        self.itable = itable
        self.gcDescriptor = gcDescriptor
    }
}

public protocol KKContinuation {
    var context: UnsafeMutableRawPointer? { get }
    func resumeWith(_ result: UnsafeMutableRawPointer?)
}

private final class RuntimeStringBox {
    let value: String

    init(_ value: String) {
        self.value = value
    }
}

private final class RuntimeThrowableBox {
    let message: String

    init(message: String) {
        self.message = message
    }
}

private enum RuntimeStorage {
    static let lock = NSLock()
    static var allocatedPointers: [UnsafeMutableRawPointer] = []
    static var objectPointers: Set<UInt> = []
    static let coroutineSuspendedBox = RuntimeStringBox("COROUTINE_SUSPENDED")
}

@_cdecl("kk_alloc")
public func kk_alloc(_ size: UInt32, _ typeInfo: UnsafeRawPointer?) -> UnsafeMutableRawPointer {
    let allocationSize = Int(max(size, 1))
    let ptr = UnsafeMutableRawPointer.allocate(byteCount: allocationSize, alignment: MemoryLayout<UInt64>.alignment)
    ptr.initializeMemory(as: UInt8.self, repeating: 0, count: allocationSize)
    RuntimeStorage.lock.lock()
    RuntimeStorage.allocatedPointers.append(ptr)
    RuntimeStorage.lock.unlock()
    _ = typeInfo
    return ptr
}

@_cdecl("kk_gc_collect")
public func kk_gc_collect() {
    // Placeholder GC implementation: no collection yet.
}

@_cdecl("kk_write_barrier")
public func kk_write_barrier(_ owner: UnsafeMutableRawPointer, _ fieldAddr: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    _ = owner
    _ = fieldAddr
    // Placeholder write barrier: no-op in current runtime.
}

@_cdecl("kk_throwable_new")
public func kk_throwable_new(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let text = extractString(from: message) ?? "Throwable"
    let throwable = RuntimeThrowableBox(message: text)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    return ptr
}

@_cdecl("kk_panic")
public func kk_panic(_ cstr: UnsafePointer<CChar>) -> Never {
    let message = String(cString: cstr)
    fatalError("KSwiftK panic: \(message)")
}

@_cdecl("kk_string_from_utf8")
public func kk_string_from_utf8(_ ptr: UnsafePointer<UInt8>, _ len: Int32) -> UnsafeMutableRawPointer {
    let count = max(0, Int(len))
    let buffer = UnsafeBufferPointer(start: ptr, count: count)
    let string = String(decoding: buffer, as: UTF8.self)
    let box = RuntimeStringBox(string)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return opaque
}

@_cdecl("kk_string_concat")
public func kk_string_concat(_ a: UnsafeMutableRawPointer?, _ b: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let lhs = extractString(from: a) ?? ""
    let rhs = extractString(from: b) ?? ""
    let box = RuntimeStringBox(lhs + rhs)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: opaque))
    RuntimeStorage.lock.unlock()
    return opaque
}

@_cdecl("kk_println_any")
public func kk_println_any(_ obj: UnsafeMutableRawPointer?) {
    guard let obj else {
        Swift.print("null")
        return
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: obj))
    RuntimeStorage.lock.unlock()
    if !isObjectPointer {
        Swift.print("<object \(obj)>")
        return
    }
    if let stringBox = tryCast(obj, to: RuntimeStringBox.self) {
        Swift.print(stringBox.value)
        return
    }
    if let throwable = tryCast(obj, to: RuntimeThrowableBox.self) {
        Swift.print("Throwable(\(throwable.message))")
        return
    }
    Swift.print("<object \(obj)>")
}

@_cdecl("kk_coroutine_suspended")
public func kk_coroutine_suspended() -> UnsafeMutableRawPointer {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(RuntimeStorage.coroutineSuspendedBox).toOpaque())
    RuntimeStorage.lock.lock()
    RuntimeStorage.objectPointers.insert(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    return ptr
}

private func tryCast<T: AnyObject>(_ ptr: UnsafeMutableRawPointer, to type: T.Type) -> T? {
    let unmanaged = Unmanaged<AnyObject>.fromOpaque(ptr)
    let anyObject = unmanaged.takeUnretainedValue()
    return anyObject as? T
}

private func extractString(from ptr: UnsafeMutableRawPointer?) -> String? {
    guard let ptr else {
        return nil
    }
    RuntimeStorage.lock.lock()
    let isObjectPointer = RuntimeStorage.objectPointers.contains(UInt(bitPattern: ptr))
    RuntimeStorage.lock.unlock()
    guard isObjectPointer else {
        return nil
    }
    guard let box = tryCast(ptr, to: RuntimeStringBox.self) else {
        return nil
    }
    return box.value
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
        DispatchQueue.global().async(execute: block)
    }

    public static func `async`(_ block: @escaping () -> UnsafeMutableRawPointer?) -> KKContinuation {
        KKDispatchContinuation(context: nil) { _ in
            _ = block()
        }
    }

    public static func delay(milliseconds: Int, continuation: KKContinuation) {
        let deadline = DispatchTime.now() + .milliseconds(max(0, milliseconds))
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            continuation.resumeWith(nil)
        }
    }
}
