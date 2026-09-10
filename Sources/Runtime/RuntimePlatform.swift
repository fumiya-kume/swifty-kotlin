import Foundation

private enum RuntimePlatformOsFamily: Int {
    case unknown = 0
    case macosx = 1
    case ios = 2
    case linux = 3
    case windows = 4
    case android = 5
    case wasm = 6
    case tvos = 7
    case watchos = 8
}

private enum RuntimePlatformCpuArchitecture: Int {
    case unknown = 0
    case arm32 = 1
    case arm64 = 2
    case x86 = 3
    case x64 = 4
    case mips32 = 5
    case mipsel32 = 6
    case wasm32 = 7
}

// MemoryModel ordinals match Kotlin stdlib MemoryModel enum:
// STRICT=0, RELAXED=1, EXPERIMENTAL=2
private enum RuntimePlatformMemoryModel: Int {
    case strict = 0
    case relaxed = 1
    case experimental = 2
}

private let runtimePlatformCanAccessUnaligned: Bool = {
#if arch(x86_64) || arch(i386) || arch(arm64)
    true
#else
    false
#endif
}()

private let runtimePlatformIsLittleEndian: Bool = {
    var value: UInt32 = 0x0102_0304
    return withUnsafeBytes(of: &value) { bytes in
        bytes.first == 0x04
    }
}()

private let runtimePlatformOsFamily: RuntimePlatformOsFamily = {
#if os(macOS)
    .macosx
#elseif os(iOS)
    .ios
#elseif os(tvOS)
    .tvos
#elseif os(watchOS)
    .watchos
#elseif os(Linux)
    .linux
#elseif os(Windows)
    .windows
#elseif os(Android)
    .android
#elseif os(WASI)
    .wasm
#else
    .unknown
#endif
}()

private let runtimePlatformCpuArchitecture: RuntimePlatformCpuArchitecture = {
#if arch(x86_64)
    .x64
#elseif arch(i386)
    .x86
#elseif arch(arm64)
    .arm64
#elseif arch(arm)
    .arm32
#elseif arch(wasm32)
    .wasm32
#else
    .unknown
#endif
}()

// Kotlin 2.3.10 exposes only EXPERIMENTAL at runtime.
private let runtimePlatformMemoryModel: RuntimePlatformMemoryModel = .experimental

private let runtimePlatformIsDebugBinary: Bool = _isDebugAssertConfiguration()
private nonisolated(unsafe) var runtimePlatformMemoryLeakCheckerActive = runtimePlatformIsDebugBinary

// Cache boxed ordinals once at startup to avoid heap allocation on every access.
private let runtimePlatformOsFamilyBoxed: Int = kk_box_int(runtimePlatformOsFamily.rawValue)
private let runtimePlatformCpuArchitectureBoxed: Int = kk_box_int(runtimePlatformCpuArchitecture.rawValue)
private let runtimePlatformMemoryModelBoxed: Int = kk_box_int(runtimePlatformMemoryModel.rawValue)

@_cdecl("kk_platform_canAccessUnaligned")
public func kk_platform_canAccessUnaligned(_ platformRaw: Int) -> Int {
    _ = platformRaw
    return runtimePlatformCanAccessUnaligned ? 1 : 0
}

@_cdecl("kk_platform_isLittleEndian")
public func kk_platform_isLittleEndian(_ platformRaw: Int) -> Int {
    _ = platformRaw
    return runtimePlatformIsLittleEndian ? 1 : 0
}

@_cdecl("kk_platform_osFamily")
public func kk_platform_osFamily(_ platformRaw: Int) -> Int {
    _ = platformRaw
    return runtimePlatformOsFamilyBoxed
}

@_cdecl("kk_platform_cpuArchitecture")
public func kk_platform_cpuArchitecture(_ platformRaw: Int) -> Int {
    _ = platformRaw
    return runtimePlatformCpuArchitectureBoxed
}

@_cdecl("kk_platform_getAvailableProcessors")
public func kk_platform_getAvailableProcessors(_ platformRaw: Int) -> Int {
    _ = platformRaw
    return max(1, ProcessInfo.processInfo.processorCount)
}

@_cdecl("kk_platform_memoryModel")
public func kk_platform_memoryModel(_ platformRaw: Int) -> Int {
    _ = platformRaw
    return runtimePlatformMemoryModelBoxed
}

@_cdecl("kk_platform_isDebugBinary")
public func kk_platform_isDebugBinary(_ platformRaw: Int) -> Int {
    _ = platformRaw
    return runtimePlatformIsDebugBinary ? 1 : 0
}

@_cdecl("kk_platform_programName")
public func kk_platform_programName(_ platformRaw: Int) -> Int {
    _ = platformRaw
    guard let programName = CommandLine.arguments.first else {
        return runtimeNullSentinelInt
    }
    return Int(bitPattern: programName.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: programName.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(programName.utf8.count))
        }
    })
}

@_cdecl("kk_platform_isMemoryLeakCheckerActive_load")
public func kk_platform_isMemoryLeakCheckerActive_load(_ platformRaw: Int) -> Int {
    _ = platformRaw
    return runtimePlatformMemoryLeakCheckerActive ? 1 : 0
}

@_cdecl("kk_platform_isMemoryLeakCheckerActive_store")
public func kk_platform_isMemoryLeakCheckerActive_store(_ platformRaw: Int, _ value: Int) -> Int {
    _ = platformRaw
    runtimePlatformMemoryLeakCheckerActive = value != 0
    return 0
}

@_cdecl("kk_platform_getAvailableProcessorsEnv")
public func kk_platform_getAvailableProcessorsEnv(_ platformRaw: Int) -> Int {
    _ = platformRaw
    guard let value = ProcessInfo.processInfo.environment["KOTLIN_NATIVE_AVAILABLE_PROCESSORS"] else {
        return runtimeNullSentinelInt
    }
    return Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}
