import Foundation
import Dispatch

final class RuntimeThreadLaunchBox: @unchecked Sendable {
    let fnPtr: Int
    let closureRaw: Int
    let isDaemon: Bool
    let contextClassLoaderRaw: Int
    let priority: Int

    init(fnPtr: Int, closureRaw: Int, isDaemon: Bool, contextClassLoaderRaw: Int, priority: Int) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.isDaemon = isDaemon
        self.contextClassLoaderRaw = contextClassLoaderRaw
        self.priority = priority
    }
}

final class RuntimeThreadLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private let completion = DispatchGroup()
    private var started = false
    private var running = false

    func markStarted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return false }
        started = true
        running = true
        completion.enter()
        return true
    }

    func markFinished() {
        lock.lock()
        let shouldLeave = running
        running = false
        lock.unlock()
        if shouldLeave {
            completion.leave()
        }
    }

    func join() {
        lock.lock()
        let shouldWait = running
        lock.unlock()
        if shouldWait {
            completion.wait()
        }
    }
}

#if canImport(ObjectiveC)
final class RuntimeManagedThread: Thread {
    var launchBox: RuntimeThreadLaunchBox?
    var launch: @Sendable () -> Void = {}
    let lifecycle = RuntimeThreadLifecycle()

    override init() {
        super.init()
    }

    override func main() {
        launch()
    }
}
#else
/// On Linux, `Foundation.Thread` cannot be subclassed because
/// swift-corelibs-foundation exposes overridable members that fail to
/// load at compile time.  We use a plain class with `pthread_create`
/// instead.
final class RuntimeManagedThread: @unchecked Sendable {
    var launchBox: RuntimeThreadLaunchBox?
    var launch: @Sendable () -> Void = {}
    let lifecycle = RuntimeThreadLifecycle()
    var name: String?
    var threadPriority: Double = 0.5

    func start() {
        let work = launch
        Thread.detachNewThread {
            work()
        }
    }
}
#endif

private func runtimeManagedThread(from raw: Int) -> RuntimeManagedThread? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeManagedThread.self)
}

private func runtimeFoundationThread(from raw: Int) -> Thread? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: Thread.self)
}

@_cdecl("kk_thread_create")
public func kk_thread_create(
    _ startRaw: Int,
    _ isDaemonRaw: Int,
    _ contextClassLoaderRaw: Int,
    _ nameRaw: Int,
    _ priorityRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int
) -> Int {
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_thread_create received invalid block")
    }

    let launch = RuntimeThreadLaunchBox(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        isDaemon: isDaemonRaw != 0,
        contextClassLoaderRaw: contextClassLoaderRaw,
        priority: priorityRaw
    )

    let thread = RuntimeManagedThread()
    thread.launchBox = launch
    let lifecycle = thread.lifecycle
    thread.launch = {
        defer { lifecycle.markFinished() }
        var thrown = 0
        _ = runtimeInvokeClosureThunk(
            fnPtr: launch.fnPtr,
            closureRaw: launch.closureRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            let errorMessage = "Thread exception occurred in kk_thread_create block (diagnostic code: \(runtimePanicDiagnosticCode), thrown: \(thrown))"
            print("[ERROR] RuntimeThread: \(errorMessage)")
            return
        }
    }

    if let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) {
        thread.name = name
    }
    if priorityRaw >= 0 {
        thread.threadPriority = min(max(Double(priorityRaw) / 10.0, 0.0), 1.0)
    }

    if startRaw != 0, thread.lifecycle.markStarted() {
        thread.start()
    }

    return registerRuntimeObject(thread)
}

@_cdecl("kk_thread_sleep")
public func kk_thread_sleep(_ millis: Int) -> Int {
    if millis > 0 {
        Thread.sleep(forTimeInterval: Double(millis) / 1000.0)
    }
    return 0
}

@_cdecl("kk_thread_currentThread")
public func kk_thread_currentThread() -> Int {
    registerRuntimeObject(Thread.current)
}

@_cdecl("kk_thread_join")
public func kk_thread_join(_ threadRaw: Int) -> Int {
    if let thread = runtimeManagedThread(from: threadRaw) {
        thread.lifecycle.join()
        return 0
    }
    guard let thread = runtimeFoundationThread(from: threadRaw) else {
        return 0
    }
    if thread === Thread.current {
        return 0
    }
    while !thread.isFinished {
        Thread.sleep(forTimeInterval: 0.001)
    }
    return 0
}
