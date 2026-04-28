import Foundation

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
