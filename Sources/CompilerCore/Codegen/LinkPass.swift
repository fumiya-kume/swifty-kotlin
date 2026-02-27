import Foundation

public final class LinkPhase: CompilerPhase {
    public static let name = "Link"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        if ctx.options.emit != .executable {
            return
        }

        guard let objectPath = ctx.generatedObjectPath,
              FileManager.default.fileExists(atPath: objectPath) else {
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

        let wrapperSource = """
        #include <stdint.h>
        #include <stddef.h>
        #include <stdio.h>
        extern intptr_t \(entrySymbol)(intptr_t* outThrown);
        int main(void) {
          intptr_t thrown = 0;
          intptr_t result = \(entrySymbol)(&thrown);
          if (thrown != 0) {
            fprintf(
              stderr,
              "KSwiftK panic [KSWIFTK-LINK-0003]: Unhandled top-level exception (%p)\\n",
              (void*)(uintptr_t)thrown
            );
            return 1;
          }
          return (int)result;
        }
        """
        let wrapperURL = stableEntryWrapperURL(outputPath: ctx.options.outputPath)
        let autoLinkedObjects = discoverLibraryObjects(searchPaths: ctx.options.searchPaths)

        do {
            try writeIfChanged(content: wrapperSource, to: wrapperURL)

            var linkInputs: [String] = [objectPath, wrapperURL.path]
            if let stubPath = ctx.runtimeStubObjectPath,
               FileManager.default.fileExists(atPath: stubPath) {
                linkInputs.append(stubPath)
            }
            for extraObject in autoLinkedObjects where !linkInputs.contains(extraObject) {
                linkInputs.append(extraObject)
            }

            var args: [String] = linkInputs
            if ctx.options.debugInfo {
                args.append("-g")
            }
            // P5-111: On Linux, only use -no-pie for debug builds that contain
            // global variables (e.g. object singleton member properties) that
            // currently need non-PIC relocations. This preserves PIE/ASLR for
            // release builds and for programs that don't use globals.
            #if os(Linux)
            let hasGlobals = kir.arena.declarations.contains { decl in
                if case .global = decl { return true }
                return false
            }
            if hasGlobals && ctx.options.debugInfo {
                args.append("-no-pie")
                ctx.diagnostics.warning(
                    "KSWIFTK-LINK-0004",
                    "Debug build with global variables: linking with -no-pie, which disables PIE/ASLR on this binary.",
                    range: nil
                )
            }
            #endif
            args.append("-o")
            args.append(ctx.options.outputPath)
            args.append(contentsOf: clangTargetArgs(ctx.options.target))
            for path in ctx.options.libraryPaths {
                args.append("-L\(path)")
            }
            for library in ctx.options.linkLibraries {
                args.append("-l\(library)")
            }
            let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
            _ = try CommandRunner.run(
                executable: clangPath,
                arguments: args,
                phaseTimer: ctx.phaseTimer,
                subPhaseName: "Link/clang"
            )
        } catch let error as CommandRunnerError {
            let message: String
            switch error {
            case .launchFailed(let reason):
                message = "Failed to launch linker: \(reason)"
            case .nonZeroExit(let result):
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
            guard case .function(let function) = decl else {
                continue
            }
            if interner.resolve(function.name) == "main" {
                return LLVMBackend.cFunctionSymbol(for: function, interner: interner)
            }
        }
        return nil
    }

    private func clangTargetArgs(_ target: TargetTriple) -> [String] {
        var triple = "\(target.arch)-\(target.vendor)-\(target.os)"
        if let version = target.osVersion, !version.isEmpty {
            triple += version
        }
        return ["-target", triple]
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

    /// Returns a deterministic URL for the entry wrapper C source file,
    /// derived from the output path so the same compilation reuses the file.
    /// Files are placed under a dedicated `kswiftk` subdirectory to avoid
    /// collisions with unrelated entries in the shared temp directory.
    private func stableEntryWrapperURL(outputPath: String) -> URL {
        let key = LLVMBackend.stableFNV1a64Hex(outputPath)
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(
                Data("warning: failed to create cache directory at \(cacheDir.path): \(error)\n".utf8)
            )
        }
        return cacheDir.appendingPathComponent("entry_\(key).c")
    }

    /// Writes `content` to `url` only when the file does not already exist
    /// or when the existing content differs, avoiding unnecessary I/O and
    /// downstream rebuilds.
    private func writeIfChanged(content: String, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let existing = try String(contentsOf: url, encoding: .utf8)
                if existing == content {
                    return
                }
            } catch {
                FileHandle.standardError.write(
                    Data("warning: failed to read existing file at \(url.path); overwriting. Error: \(error)\n".utf8)
                )
            }
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func objectPaths(from libraryDir: String) -> [String] {
        let fileManager = FileManager.default
        let manifestPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("manifest.json").path
        if let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let manifestObjects = object["objects"] as? [String] {
            let mapped = manifestObjects
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: libraryDir).appendingPathComponent($0).path }
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
