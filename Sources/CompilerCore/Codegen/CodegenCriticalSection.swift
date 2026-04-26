import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum CodegenCriticalSection {
    static func withLinuxExecutableToolchainLock<T>(
        target: TargetTriple,
        body: () throws -> T
    ) throws -> T {
        guard target.os.hasPrefix("linux") else {
            return try body()
        }

        let lockDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-codegen-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)

        let targetKey = CodegenRuntimeSupport.stableFNV1a64Hex(CodegenRuntimeSupport.targetTripleString(target))
        let lockURL = lockDirectory.appendingPathComponent("executable-toolchain-\(targetKey).lock")
        let descriptor = lockURL.path.withCString { path in
            open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw CodegenCriticalSectionError.systemCallFailed("open", errno)
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw CodegenCriticalSectionError.systemCallFailed("flock", errno)
        }
        defer { _ = flock(descriptor, LOCK_UN) }

        return try body()
    }
}

private enum CodegenCriticalSectionError: Error, CustomStringConvertible {
    case systemCallFailed(String, Int32)

    var description: String {
        switch self {
        case let .systemCallFailed(operation, errorCode):
            return "\(operation) failed: \(String(cString: strerror(errorCode)))"
        }
    }
}
