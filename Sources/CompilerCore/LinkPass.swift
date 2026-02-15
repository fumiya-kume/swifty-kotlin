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
        extern intptr_t \(entrySymbol)(intptr_t* outThrown);
        int main(void) { return (int)\(entrySymbol)(NULL); }
        """
        let wrapperURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_entry.c")
        defer { try? FileManager.default.removeItem(at: wrapperURL) }

        do {
            try wrapperSource.write(to: wrapperURL, atomically: true, encoding: .utf8)

            var args: [String] = [objectPath, wrapperURL.path, "-o", ctx.options.outputPath]
            args.append(contentsOf: clangTargetArgs(ctx.options.target))
            for path in ctx.options.libraryPaths {
                args.append("-L\(path)")
            }
            for library in ctx.options.linkLibraries {
                args.append("-l\(library)")
            }
            _ = try CommandRunner.run(executable: "/usr/bin/clang", arguments: args)
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
}
