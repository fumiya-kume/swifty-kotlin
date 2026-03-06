import Foundation

/// Lock-protected cache for pre-compiled runtime stub objects.
final class RuntimeStubCache: @unchecked Sendable {
    private enum StubLockAcquisition {
        case acquired
        case artifactAvailable
        case timedOut
    }

    private static let compilationLockPollInterval: TimeInterval = 0.05
    private static let compilationLockStaleAge: TimeInterval = 30
    private static let compilationLockTimeout: TimeInterval = 60

    private let lock = NSLock()
    private var cache: [String: String] = [:]

    func getOrInsert(triple: String, context: StubCompilationContext) -> String? {
        lock.lock()
        if let cached = cache[triple], FileManager.default.fileExists(atPath: cached) {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let compiled = Self.compileStub(context: context) else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[triple], FileManager.default.fileExists(atPath: cached) {
            return cached
        }
        cache[triple] = compiled
        return compiled
    }

    private static func compileStub(context: StubCompilationContext) -> String? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: context.stubDir, withIntermediateDirectories: true)

        let stubObject = context.stubDir.appendingPathComponent("kk_runtime_\(context.cacheKey).o")
        let lockDir = context.stubDir.appendingPathComponent("kk_runtime_\(context.cacheKey).lock", isDirectory: true)

        if fileManager.fileExists(atPath: stubObject.path) {
            return stubObject.path
        }

        switch acquireCompilationLock(lockDir: lockDir, artifactURL: stubObject) {
        case .artifactAvailable:
            return stubObject.path
        case .timedOut:
            return nil
        case .acquired:
            break
        }

        defer {
            try? fileManager.removeItem(at: lockDir)
        }

        if fileManager.fileExists(atPath: stubObject.path) {
            return stubObject.path
        }

        let tempToken = "\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"
        let stubSource = context.stubDir.appendingPathComponent("kk_runtime_\(context.cacheKey)_\(tempToken).c")
        let tempObject = context.stubDir.appendingPathComponent("kk_runtime_\(context.cacheKey)_\(tempToken).o")

        defer {
            try? fileManager.removeItem(at: stubSource)
            try? fileManager.removeItem(at: tempObject)
        }

        do {
            try context.source.write(to: stubSource, atomically: true, encoding: .utf8)
            let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
            var args = ["-x", "c", "-std=c11", "-c", stubSource.path, "-o", tempObject.path]
            args.append(contentsOf: context.clangTargetArgs)
            _ = try CommandRunner.run(
                executable: clangPath,
                arguments: args,
                phaseTimer: nil,
                subPhaseName: "Codegen/clang-stub"
            )

            try publishCompiledStub(from: tempObject, to: stubObject)
            return stubObject.path
        } catch {
            return nil
        }
    }

    private static func acquireCompilationLock(lockDir: URL, artifactURL: URL) -> StubLockAcquisition {
        let fileManager = FileManager.default
        let deadline = Date().addingTimeInterval(compilationLockTimeout)

        while true {
            do {
                try fileManager.createDirectory(at: lockDir, withIntermediateDirectories: false)
                return .acquired
            } catch {
                if fileManager.fileExists(atPath: artifactURL.path) {
                    return .artifactAvailable
                }

                if isStaleLock(lockDir: lockDir) {
                    try? fileManager.removeItem(at: lockDir)
                    continue
                }

                if Date() >= deadline {
                    return fileManager.fileExists(atPath: artifactURL.path) ? .artifactAvailable : .timedOut
                }

                Thread.sleep(forTimeInterval: compilationLockPollInterval)
            }
        }
    }

    private static func isStaleLock(lockDir: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: lockDir.path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return false
        }

        return Date().timeIntervalSince(modifiedAt) > compilationLockStaleAge
    }

    private static func publishCompiledStub(from tempObject: URL, to finalObject: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: finalObject.path) {
            return
        }

        do {
            try fileManager.moveItem(at: tempObject, to: finalObject)
        } catch {
            if fileManager.fileExists(atPath: finalObject.path) {
                return
            }
            throw error
        }
    }
}

/// Immutable context for compiling a runtime stub.
struct StubCompilationContext {
    let source: String
    let cacheKey: String
    let clangTargetArgs: [String]
    let stubDir: URL
}

public struct RuntimeLinkInfo {
    public let libraryPaths: [String]
    public let libraries: [String]
    public let extraObjects: [String]

    public init(libraryPaths: [String], libraries: [String], extraObjects: [String]) {
        self.libraryPaths = libraryPaths
        self.libraries = libraries
        self.extraObjects = extraObjects
    }
}
