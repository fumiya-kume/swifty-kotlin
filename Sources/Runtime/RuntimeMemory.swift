import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - Memory management runtime support (STDLIB-PERF-154)

struct RuntimeMemorySnapshot: Equatable, Sendable {
    let totalBytes: Int64
    let freeBytes: Int64
    let maxBytes: Int64
}

final class RuntimeMemoryHandle: @unchecked Sendable {
    static let shared = RuntimeMemoryHandle()
    private init() {}
}

private let runtimeMemoryHandleRaw: Int = registerRuntimeObject(RuntimeMemoryHandle.shared)

func runtimeCaptureMemorySnapshot() -> RuntimeMemorySnapshot {
    let usedBytes = runtimeCurrentMemoryUsageBytes()
    let maxBytes = runtimeMaximumMemoryBytes()
    let totalBytes = min(max(usedBytes, 0), maxBytes)
    let freeBytes = max(maxBytes - totalBytes, 0)
    return RuntimeMemorySnapshot(
        totalBytes: totalBytes,
        freeBytes: freeBytes,
        maxBytes: maxBytes
    )
}

private func runtimeMaximumMemoryBytes() -> Int64 {
    Int64(clamping: ProcessInfo.processInfo.physicalMemory)
}

private func runtimeCurrentMemoryUsageBytes() -> Int64 {
#if canImport(Darwin)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), reboundPtr, &count)
        }
    }
    if result == KERN_SUCCESS {
        return Int64(info.resident_size)
    }
    return 0
#elseif canImport(Glibc)
    guard let statm = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8) else {
        return 0
    }
    let fields = statm.split(whereSeparator: \.isWhitespace)
    guard fields.count > 1, let residentPages = Int64(fields[1]) else {
        return 0
    }
    let pageSize = Int64(sysconf(Int32(_SC_PAGESIZE)))
    return residentPages * max(pageSize, 1)
#else
    return 0
#endif
}

@_cdecl("__kk_system_gc")
public func __kk_system_gc() {
    kk_gc_collect()
}

@_cdecl("__kk_runtime_getRuntime")
public func __kk_runtime_getRuntime() -> Int {
    runtimeMemoryHandleRaw
}

@_cdecl("__kk_runtime_totalMemory")
public func __kk_runtime_totalMemory() -> Int {
    Int(clamping: runtimeCaptureMemorySnapshot().totalBytes)
}

@_cdecl("__kk_runtime_freeMemory")
public func __kk_runtime_freeMemory() -> Int {
    Int(clamping: runtimeCaptureMemorySnapshot().freeBytes)
}

@_cdecl("__kk_runtime_maxMemory")
public func __kk_runtime_maxMemory() -> Int {
    Int(clamping: runtimeCaptureMemorySnapshot().maxBytes)
}

// MARK: - Java class runtime support

final class RuntimeJavaClassBox: @unchecked Sendable {
    let receiverRaw: Int

    init(receiverRaw: Int) {
        self.receiverRaw = receiverRaw
    }
}

@_cdecl("__kk_any_javaClass")
public func __kk_any_javaClass(_ receiverRaw: Int) -> Int {
    registerRuntimeObject(RuntimeJavaClassBox(receiverRaw: receiverRaw))
}
