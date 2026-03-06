import Foundation

public final class LinkPhase: CompilerPhase {
    public static let name = "Link"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        if ctx.options.emit != .executable {
            return
        }

        guard let objectPath = ctx.generatedObjectPath,
              FileManager.default.fileExists(atPath: objectPath)
        else {
            throw CompilerPipelineError.outputUnavailable
        }

        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available during link.")
        }

        guard let entrySymbol = resolveEntrySymbol(kir: kir, interner: ctx.interner) else {
            ctx.diagnostics.error(
                "KSWIFTK-LINK-0002",
                "No entry point 'main' function found for executable emission.",
                range: nil
            )
            throw CompilerPipelineError.outputUnavailable
        }

        let autoLinkedObjects = discoverLibraryObjects(searchPaths: ctx.options.searchPaths)

        do {
            let runtimeObjects = try CodegenRuntimeSupport.runtimeObjectPaths(target: ctx.options.target)
            let entryWrapperObjectPath = try LLVMEntryPointObjectEmitter(target: ctx.options.target)
                .emit(entrySymbol: entrySymbol, outputPath: ctx.options.outputPath)
            var linkInputs: [String] = [objectPath, entryWrapperObjectPath]
            for runtimeObject in runtimeObjects where !linkInputs.contains(runtimeObject) {
                linkInputs.append(runtimeObject)
            }
            for extraObject in autoLinkedObjects where !linkInputs.contains(extraObject) {
                linkInputs.append(extraObject)
            }

            var args: [String] = linkInputs
            if ctx.options.debugInfo {
                args.append("-g")
            }
            args.append("-o")
            args.append(ctx.options.outputPath)
            args.append(contentsOf: linkerTargetArgs(ctx.options.target))
            for path in ctx.options.libraryPaths {
                args.append("-L\(path)")
            }
            for library in ctx.options.linkLibraries {
                args.append("-l\(library)")
            }
            let swiftcPath = CommandRunner.resolveExecutable("swiftc", fallback: "/usr/bin/swiftc")
            _ = try CommandRunner.run(
                executable: swiftcPath,
                arguments: args,
                phaseTimer: ctx.phaseTimer,
                subPhaseName: "Link/swiftc"
            )
        } catch let error as CommandRunnerError {
            let message: String
            switch error {
            case let .launchFailed(reason):
                message = "Failed to launch linker: \(reason)"
            case let .nonZeroExit(result):
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                message = stderr.isEmpty ? "Linker failed with exit code \(result.exitCode)." : "Linker failed: \(stderr)"
            }
            ctx.diagnostics.error("KSWIFTK-LINK-0001", message, range: nil)
            throw CompilerPipelineError.outputUnavailable
        } catch {
            ctx.diagnostics.error("KSWIFTK-LINK-0001", "Link step failed: \(error)", range: nil)
            throw CompilerPipelineError.outputUnavailable
        }
    }

    private func resolveEntrySymbol(kir: KIRModule, interner: StringInterner) -> String? {
        for decl in kir.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            if interner.resolve(function.name) == "main" {
                return CodegenSymbolSupport.cFunctionSymbol(for: function, interner: interner)
            }
        }
        return nil
    }

    private func linkerTargetArgs(_ target: TargetTriple) -> [String] {
        ["-target", linkerTargetTriple(target)]
    }

    private func linkerTargetTriple(_ target: TargetTriple) -> String {
        if let version = target.osVersion, !version.isEmpty {
            return CodegenRuntimeSupport.targetTripleString(target)
        }
        if target.vendor == "apple", target.os == "macosx" {
            let minimumVersion = target.arch == "arm64" ? "11.0" : "10.9"
            return CodegenRuntimeSupport.targetTripleString(target) + minimumVersion
        }
        return CodegenRuntimeSupport.targetTripleString(target)
    }

    private func discoverLibraryObjects(searchPaths: [String]) -> [String] {
        let fileManager = FileManager.default
        var libraryDirs: Set<String> = []
        for rawPath in searchPaths {
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if path.hasSuffix(".kklib") {
                libraryDirs.insert(path)
                continue
            }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".kklib") {
                libraryDirs.insert(URL(fileURLWithPath: path).appendingPathComponent(entry).standardizedFileURL.path)
            }
        }

        var collected: [String] = []
        var seen: Set<String> = []
        for libraryDir in libraryDirs.sorted() {
            for objectPath in objectPaths(from: libraryDir) {
                let absolutePath = URL(fileURLWithPath: objectPath).standardizedFileURL.path
                guard fileManager.fileExists(atPath: absolutePath) else {
                    continue
                }
                if seen.insert(absolutePath).inserted {
                    collected.append(absolutePath)
                }
            }
        }
        return collected
    }

    private func objectPaths(from libraryDir: String) -> [String] {
        let fileManager = FileManager.default
        let manifestPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("manifest.json").path
        if let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let manifestObjects = object["objects"] as? [String]
        {
            let libraryDirNormalized = URL(fileURLWithPath: libraryDir).standardized.path
            let mapped = manifestObjects
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: libraryDir).appendingPathComponent($0).standardized.path }
                .filter { $0.hasPrefix(libraryDirNormalized + "/") }
            if !mapped.isEmpty {
                return mapped
            }
        }

        let objectsDir = URL(fileURLWithPath: libraryDir).appendingPathComponent("objects").path
        guard let entries = try? fileManager.contentsOfDirectory(atPath: objectsDir) else {
            return []
        }
        return entries
            .filter { $0.hasSuffix(".o") }
            .sorted()
            .map { URL(fileURLWithPath: objectsDir).appendingPathComponent($0).path }
    }
}
