import Foundation

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

#if canImport(ObjectiveC)
final class RuntimeManagedThread: Thread {
    var launchBox: RuntimeThreadLaunchBox?
    var launch: @Sendable () -> Void = {}

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
    thread.launch = {
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

    if startRaw != 0 {
        thread.start()
    }

    return registerRuntimeObject(thread)
}
