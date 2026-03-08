import Foundation

private final class RuntimeObjectCache: @unchecked Sendable {
    private let condition = NSCondition()
    private var cachedPathsByTarget: [String: [String]] = [:]
    private var loadingKeys: Set<String> = []

    func getOrLoad(cacheKey: String, loader: () throws -> [String]) throws -> [String] {
        condition.lock()
        while true {
            if let cachedPaths = cachedPathsIfValid(for: cacheKey) {
                condition.unlock()
                return cachedPaths
            }
            if !loadingKeys.contains(cacheKey) {
                loadingKeys.insert(cacheKey)
                condition.unlock()

                do {
                    let loadedPaths = try loader()
                    condition.lock()
                    cachedPathsByTarget[cacheKey] = loadedPaths
                    loadingKeys.remove(cacheKey)
                    condition.broadcast()
                    condition.unlock()
                    return loadedPaths
                } catch {
                    condition.lock()
                    loadingKeys.remove(cacheKey)
                    condition.broadcast()
                    condition.unlock()
                    throw error
                }
            }
            condition.wait()
        }
    }

    private func cachedPathsIfValid(for cacheKey: String) -> [String]? {
        guard let cachedPaths = cachedPathsByTarget[cacheKey],
              cachedPaths.allSatisfy({ FileManager.default.fileExists(atPath: $0) })
        else {
            return nil
        }
        return cachedPaths
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
        let cacheKey = runtimeBuildCacheKey(target: target)
        return try runtimeObjectCache.getOrLoad(cacheKey: cacheKey) {
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
        runtimeBuildScratchDirectory(target: target)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("Runtime.build", isDirectory: true)
    }

    private static func runtimeBuildRootDirectory(target: TargetTriple) -> URL {
        runtimeScratchRootDirectory()
            .appendingPathComponent(runtimeBuildCacheKey(target: target), isDirectory: true)
    }

    private static func swiftBuildArguments(target: TargetTriple) -> [String] {
        var arguments = [
            "build",
            "--target", "Runtime",
            "--disable-code-coverage",
            "--scratch-path", runtimeBuildScratchDirectory(target: target).path,
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
        if let overridePath = ProcessInfo.processInfo.environment["KSWIFTK_PACKAGE_ROOT"] {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            if let root = firstAncestorContainingPackage(startingAt: overrideURL) {
                return root
            }
        }

        let fileManager = FileManager.default
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if let root = firstAncestorContainingPackage(startingAt: currentDirectoryURL) {
            return root
        }

        if let executablePath = CommandLine.arguments.first, !executablePath.isEmpty {
            let executableURL = URL(fileURLWithPath: executablePath)
            if let root = firstAncestorContainingPackage(startingAt: executableURL.deletingLastPathComponent()) {
                return root
            }
        }

        let sourceRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return firstAncestorContainingPackage(startingAt: sourceRootURL) ?? sourceRootURL
    }

    private static func firstAncestorContainingPackage(startingAt url: URL) -> URL? {
        var current = url.standardizedFileURL
        let fileManager = FileManager.default
        while true {
            if fileManager.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private static func runtimeBuildScratchDirectory(target: TargetTriple) -> URL {
        runtimeBuildRootDirectory(target: target)
    }

    private static func runtimeBuildCacheKey(target: TargetTriple) -> String {
        "runtime-nocov-v2-\(targetTripleString(target))-\(runtimeSourceFingerprint())"
    }

    private static func runtimeSourceFingerprint() -> String {
        let runtimeSourcesURL = packageRootURL()
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Runtime", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: runtimeSourcesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return "runtime-sources-missing"
        }

        let files = (enumerator.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }

        var payload = ""
        payload.reserveCapacity(files.count * 256)
        for fileURL in files {
            payload.append(fileURL.path)
            payload.append("\u{0}")
            if let data = try? Data(contentsOf: fileURL) {
                payload.append(String(decoding: data, as: UTF8.self))
            }
            payload.append("\u{1}")
        }
        return stableFNV1a64Hex(payload)
    }
}
