import Foundation

private let currentKotlinVersion = (major: 2, minor: 3, patch: 20)

final class RuntimeKotlinVersionBox {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

private func runtimeKotlinVersionBox(from raw: Int) -> RuntimeKotlinVersionBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKotlinVersionBox.self)
}

@_cdecl("kk_kotlin_version_new")
public func kk_kotlin_version_new(_ major: Int, _ minor: Int) -> Int {
    registerRuntimeObject(RuntimeKotlinVersionBox(major: major, minor: minor, patch: 0))
}

@_cdecl("kk_kotlin_version_new_patch")
public func kk_kotlin_version_new_patch(_ major: Int, _ minor: Int, _ patch: Int) -> Int {
    registerRuntimeObject(RuntimeKotlinVersionBox(major: major, minor: minor, patch: patch))
}

@_cdecl("kk_kotlin_version_current")
public func kk_kotlin_version_current() -> Int {
    registerRuntimeObject(RuntimeKotlinVersionBox(
        major: currentKotlinVersion.major,
        minor: currentKotlinVersion.minor,
        patch: currentKotlinVersion.patch
    ))
}

@_cdecl("kk_kotlin_version_major")
public func kk_kotlin_version_major(_ versionRaw: Int) -> Int {
    runtimeKotlinVersionBox(from: versionRaw)?.major ?? 0
}

@_cdecl("kk_kotlin_version_minor")
public func kk_kotlin_version_minor(_ versionRaw: Int) -> Int {
    runtimeKotlinVersionBox(from: versionRaw)?.minor ?? 0
}

@_cdecl("kk_kotlin_version_patch")
public func kk_kotlin_version_patch(_ versionRaw: Int) -> Int {
    runtimeKotlinVersionBox(from: versionRaw)?.patch ?? 0
}

@_cdecl("kk_kotlin_version_compareTo")
public func kk_kotlin_version_compareTo(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeKotlinVersionBox(from: lhsRaw),
          let rhs = runtimeKotlinVersionBox(from: rhsRaw)
    else {
        return 0
    }
    return lhs.compare(to: rhs)
}

@_cdecl("kk_kotlin_version_isAtLeast")
public func kk_kotlin_version_isAtLeast(_ versionRaw: Int, _ major: Int, _ minor: Int) -> Int {
    kk_kotlin_version_isAtLeast_patch(versionRaw, major, minor, 0)
}

@_cdecl("kk_kotlin_version_isAtLeast_patch")
public func kk_kotlin_version_isAtLeast_patch(_ versionRaw: Int, _ major: Int, _ minor: Int, _ patch: Int) -> Int {
    guard let version = runtimeKotlinVersionBox(from: versionRaw) else {
        return 0
    }
    let minimum = RuntimeKotlinVersionBox(major: major, minor: minor, patch: patch)
    return version.compare(to: minimum) >= 0 ? 1 : 0
}

private extension RuntimeKotlinVersionBox {
    func compare(to other: RuntimeKotlinVersionBox) -> Int {
        if major != other.major {
            return major < other.major ? -1 : 1
        }
        if minor != other.minor {
            return minor < other.minor ? -1 : 1
        }
        if patch != other.patch {
            return patch < other.patch ? -1 : 1
        }
        return 0
    }
}
