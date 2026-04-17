import Foundation

private enum RuntimePlatformOsFamily: Int {
    case unknown = 0
    case macosx = 1
    case ios = 2
    case tvos = 3
    case watchos = 4
    case linux = 5
    case windows = 6
    case android = 7
    case wasm = 8
}

private enum RuntimePlatformCpuArchitecture: Int {
    case unknown = 0
    case x86 = 1
    case x64 = 2
    case arm32 = 3
    case arm64 = 4
    case mips32 = 5
    case mipsel32 = 6
    case wasm32 = 7
}

// MemoryModel ordinals match Kotlin stdlib MemoryModel enum:
// EXPERIMENTAL=0, STRICT=1, RELAXED=2
private enum RuntimePlatformMemoryModel: Int {
    case experimental = 0
    case strict = 1
    case relaxed = 2
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

private let runtimePlatformMemoryModel: RuntimePlatformMemoryModel = {
#if KSWIFTK_MEMORY_MODEL_STRICT
    .strict
#elseif KSWIFTK_MEMORY_MODEL_RELAXED
    .relaxed
#else
    .experimental
#endif
}()

private let runtimePlatformIsDebugBinary: Bool = _isDebugAssertConfiguration()

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
