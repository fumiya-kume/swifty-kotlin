import Foundation

private final class RuntimeObjectCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedPathsByTarget: [String: [String]] = [:]

    func getOrLoad(cacheKey: String, loader: () throws -> [String]) throws -> [String] {
        lock.lock()
        if let cachedPaths = cachedPathsByTarget[cacheKey],
           cachedPaths.allSatisfy({ FileManager.default.fileExists(atPath: $0) })
        {
            lock.unlock()
            return cachedPaths
        }
        lock.unlock()

        let loadedPaths = try loader()

        lock.lock()
        cachedPathsByTarget[cacheKey] = loadedPaths
        lock.unlock()
        return loadedPaths
    }
}

enum CodegenRuntimeSupportError: Error, CustomStringConvertible {
    case runtimeObjectsUnavailable(String)
    case runtimeBuildFailed(String)

    var description: String {
        switch self {
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
        let requestedTriple = targetTripleString(target)
        return try runtimeObjectCache.getOrLoad(cacheKey: requestedTriple) {
            let discovered = discoverRuntimeObjectPaths(target: target)
            if !discovered.isEmpty {
                return discovered
            }

            try buildRuntimeObjects(target: target)

            let built = discoverRuntimeObjectPaths(target: target)
            guard !built.isEmpty else {
                throw CodegenRuntimeSupportError.runtimeObjectsUnavailable(runtimeBuildDirectory(target: target).path)
            }
            return built
        }
    }

    private static func buildRuntimeObjects(target: TargetTriple) throws {
        let swiftPath = CommandRunner.resolveExecutable("swift", fallback: "/usr/bin/swift")
        do {
            _ = try CommandRunner.run(
                executable: swiftPath,
                arguments: swiftBuildArguments(target: target),
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

    private static func discoverRuntimeObjectPaths(target: TargetTriple) -> [String] {
        var candidates = collectObjectPaths(in: runtimeBuildDirectory(target: target))
        if !candidates.isEmpty {
            return candidates
        }

        let buildRoot = runtimeBuildRootDirectory(target: target)
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

    private static func runtimeBuildDirectory(target: TargetTriple) -> URL {
        runtimeBuildRootDirectory(target: target)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("Runtime.build", isDirectory: true)
    }

    private static func runtimeBuildRootDirectory(target: TargetTriple) -> URL {
        runtimeScratchRootDirectory()
            .appendingPathComponent(targetTripleString(target), isDirectory: true)
    }

    private static func swiftBuildArguments(target: TargetTriple) -> [String] {
        var arguments = [
            "build",
            "--target", "Runtime",
            "--scratch-path", runtimeScratchRootDirectory().path,
        ]
        if target != TargetTriple.hostDefault() {
            arguments.append(contentsOf: ["--triple", targetTripleString(target)])
        }
        return arguments
    }

    private static func runtimeScratchRootDirectory() -> URL {
        packageRootURL().appendingPathComponent(".runtime-build", isDirectory: true)
    }

    private static func packageRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
