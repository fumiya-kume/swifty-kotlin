import Foundation

/// Lock-protected cache for pre-compiled runtime stub objects.
final class RuntimeStubCache: @unchecked Sendable {
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
        try? FileManager.default.createDirectory(at: context.stubDir, withIntermediateDirectories: true)

        let stubSource = context.stubDir.appendingPathComponent("kk_runtime_\(context.cacheKey).c")
        let stubObject = context.stubDir.appendingPathComponent("kk_runtime_\(context.cacheKey).o")

        if FileManager.default.fileExists(atPath: stubObject.path) {
            return stubObject.path
        }
        do {
            try context.source.write(to: stubSource, atomically: true, encoding: .utf8)
            let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
            var args = ["-x", "c", "-std=c11", "-c", stubSource.path, "-o", stubObject.path]
            args.append(contentsOf: context.clangTargetArgs)
            _ = try CommandRunner.run(
                executable: clangPath,
                arguments: args,
                phaseTimer: nil,
                subPhaseName: "Codegen/clang-stub"
            )
            return stubObject.path
        } catch {
            return nil
        }
    }
}

/// Immutable context for compiling a runtime stub.
struct StubCompilationContext: Sendable {
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
