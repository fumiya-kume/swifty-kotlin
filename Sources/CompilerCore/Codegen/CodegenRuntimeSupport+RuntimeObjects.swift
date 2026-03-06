import Foundation

private final class RuntimeObjectCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedPaths: [String]?

    func getOrLoad(loader: () throws -> [String]) throws -> [String] {
        lock.lock()
        if let cachedPaths, cachedPaths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) {
            lock.unlock()
            return cachedPaths
        }
        lock.unlock()

        let loadedPaths = try loader()

        lock.lock()
        cachedPaths = loadedPaths
        lock.unlock()
        return loadedPaths
    }
}

enum CodegenRuntimeSupportError: Error, CustomStringConvertible {
    case unsupportedTarget(requested: String, host: String)
    case runtimeObjectsUnavailable(String)
    case runtimeBuildFailed(String)

    var description: String {
        switch self {
        case let .unsupportedTarget(requested, host):
            "Executable linking currently supports only the host target. requested=\(requested) host=\(host)"
        case let .runtimeObjectsUnavailable(path):
            "Unable to locate packaged runtime object files under \(path)."
        case let .runtimeBuildFailed(reason):
            "Failed to build packaged runtime objects: \(reason)"
        }
    }
}

extension CodegenRuntimeSupport {
    private static let runtimeObjectCache = RuntimeObjectCache()

    static func runtimeObjectPaths(target: TargetTriple) throws -> [String] {
        let hostTarget = TargetTriple.hostDefault()
        let requestedTriple = targetTripleString(target)
        let hostTriple = targetTripleString(hostTarget)
        guard target == hostTarget else {
            throw CodegenRuntimeSupportError.unsupportedTarget(
                requested: requestedTriple,
                host: hostTriple
            )
        }

        return try runtimeObjectCache.getOrLoad {
            let discovered = discoverRuntimeObjectPaths()
            if !discovered.isEmpty {
                return discovered
            }

            try buildRuntimeObjects()

            let built = discoverRuntimeObjectPaths()
            guard !built.isEmpty else {
                throw CodegenRuntimeSupportError.runtimeObjectsUnavailable(runtimeBuildDirectory().path)
            }
            return built
        }
    }

    private static func buildRuntimeObjects() throws {
        let swiftPath = CommandRunner.resolveExecutable("swift", fallback: "/usr/bin/swift")
        do {
            _ = try CommandRunner.run(
                executable: swiftPath,
                arguments: ["build", "--target", "Runtime"],
                currentDirectoryPath: packageRootURL().path,
                phaseTimer: nil,
                subPhaseName: "Link/swift-runtime-build"
            )
        } catch let error as CommandRunnerError {
            throw CodegenRuntimeSupportError.runtimeBuildFailed(describeBuild(error))
        } catch {
            throw CodegenRuntimeSupportError.runtimeBuildFailed(String(describing: error))
        }
    }

    private static func describeBuild(_ error: CommandRunnerError) -> String {
        switch error {
        case let .launchFailed(reason):
            return reason
        case let .nonZeroExit(result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return stderr.isEmpty ? "swift build exited with code \(result.exitCode)." : stderr
        }
    }

    private static func discoverRuntimeObjectPaths() -> [String] {
        var candidates = collectObjectPaths(in: runtimeBuildDirectory())
        if !candidates.isEmpty {
            return candidates
        }

        let buildRoot = packageRootURL().appendingPathComponent(".build", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: buildRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let directoryURL as URL in enumerator {
            guard directoryURL.lastPathComponent == "Runtime.build" else {
                continue
            }
            candidates = collectObjectPaths(in: directoryURL)
            if !candidates.isEmpty {
                return candidates
            }
        }
        return []
    }

    private static func collectObjectPaths(in directory: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { $0.lastPathComponent.hasSuffix(".swift.o") }
            .map(\.path)
            .sorted()
    }

    private static func runtimeBuildDirectory() -> URL {
        packageRootURL()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent(targetTripleString(TargetTriple.hostDefault()), isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("Runtime.build", isDirectory: true)
    }

    private static func packageRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
