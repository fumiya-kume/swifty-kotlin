import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - Memory management runtime support (STDLIB-PERF-154)

struct RuntimeMemorySnapshot: Equatable, Sendable {
    let usedBytes: Int64
    let totalBytes: Int64
    let freeBytes: Int64
    let maxBytes: Int64
    let heapObjectCount: Int
    let uptimeNanos: UInt64
}

struct RuntimeMemoryLeakReport: Equatable, Sendable {
    let baseline: RuntimeMemorySnapshot
    let current: RuntimeMemorySnapshot
    let leakedBytes: Int64
    let heapObjectDelta: Int
    let thresholdBytes: Int64
    let thresholdObjectCount: Int

    var hasLeak: Bool {
        leakedBytes >= thresholdBytes || heapObjectDelta >= thresholdObjectCount
    }
}

final class RuntimeMemoryHandle: @unchecked Sendable {
    static let shared = RuntimeMemoryHandle()
    private init() {}
}

private let runtimeMemoryHandleRaw: Int = registerRuntimeObject(RuntimeMemoryHandle.shared)

func runtimeCaptureMemorySnapshot(nowNanos: UInt64 = DispatchTime.now().uptimeNanoseconds) -> RuntimeMemorySnapshot {
    let usedBytes = runtimeCurrentMemoryUsageBytes()
    let maxBytes = runtimeMaximumMemoryBytes()
    let totalBytes = min(max(usedBytes, 0), maxBytes)
    let freeBytes = max(maxBytes - totalBytes, 0)
    let heapObjectCount = runtimeStorage.withGCLock { state in
        state.heapObjects.count
    }
    return RuntimeMemorySnapshot(
        usedBytes: usedBytes,
        totalBytes: totalBytes,
        freeBytes: freeBytes,
        maxBytes: maxBytes,
        heapObjectCount: heapObjectCount,
        uptimeNanos: nowNanos
    )
}

func runtimeDetectMemoryLeak(
    since baseline: RuntimeMemorySnapshot,
    current: RuntimeMemorySnapshot = runtimeCaptureMemorySnapshot(),
    thresholdBytes: Int64 = 1 << 20,
    thresholdObjectCount: Int = 1
) -> RuntimeMemoryLeakReport {
    RuntimeMemoryLeakReport(
        baseline: baseline,
        current: current,
        leakedBytes: max(current.usedBytes - baseline.usedBytes, 0),
        heapObjectDelta: max(current.heapObjectCount - baseline.heapObjectCount, 0),
        thresholdBytes: max(thresholdBytes, 0),
        thresholdObjectCount: max(thresholdObjectCount, 0)
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

@_cdecl("kk_system_gc")
public func kk_system_gc() {
    kk_gc_collect()
}

@_cdecl("kk_runtime_getRuntime")
public func kk_runtime_getRuntime() -> Int {
    runtimeMemoryHandleRaw
}

@_cdecl("kk_runtime_totalMemory")
public func kk_runtime_totalMemory() -> Int {
    Int(clamping: runtimeCaptureMemorySnapshot().totalBytes)
}

@_cdecl("kk_runtime_freeMemory")
public func kk_runtime_freeMemory() -> Int {
    Int(clamping: runtimeCaptureMemorySnapshot().freeBytes)
}

@_cdecl("kk_runtime_maxMemory")
public func kk_runtime_maxMemory() -> Int {
    Int(clamping: runtimeCaptureMemorySnapshot().maxBytes)
}
