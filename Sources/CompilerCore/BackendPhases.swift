import Foundation

public final class DataFlowSemaPassPhase: CompilerPhase {
    public static let name = "DataFlowSemaPass"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        let declarationCount = ctx.ast?.declarationCount ?? 0
        let declarationSymbols = ctx.ast?.arena.declarations().reduce(0) { count, decl in
            switch decl {
            case .classDecl:
                return count + 1
            case .funDecl:
                return count + 1
            case .propertyDecl:
                return count + 1
            case .typeAliasDecl:
                return count + 1
            case .objectDecl:
                return count + 1
            case .enumEntry:
                return count + 1
            }
        } ?? 0
        let symbolCount = declarationSymbols
        ctx.sema = SemaModule(
            symbolCount: symbolCount,
            declarationCount: declarationCount,
            diagnostics: ctx.diagnostics
        )
    }
}

public final class TypeCheckSemaPassPhase: CompilerPhase {
    public static let name = "TypeCheckSemaPass"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard ctx.ast != nil else {
            throw CompilerPipelineError.invalidInput("No AST available for semantic analysis.")
        }
    }
}

public final class SemaPassesPhase: CompilerPhase {
    public static let name = "SemaPasses"

    private let passes: [CompilerPhase] = [
        DataFlowSemaPassPhase(),
        TypeCheckSemaPassPhase()
    ]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard ctx.ast != nil else {
            throw CompilerPipelineError.invalidInput("AST phase did not run.")
        }
        for phase in passes {
            try phase.run(ctx)
        }
    }
}

public final class BuildKIRPhase: CompilerPhase {
    public static let name = "BuildKIR"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Sema phase did not run.")
        }
        let functionCount = ctx.ast?.arena.declarations().reduce(0) { count, decl in
            if case .funDecl = decl {
                return count + 1
            }
            return count
        } ?? 0
        let symbolCount = sema.symbolCount
        if functionCount == 0 && sema.diagnostics?.hasError == false {
            sema.diagnostics?.warning(
                "KSWIFTK-KIR-0001",
                "No function declarations found.",
                range: nil
            )
        }
        ctx.kir = KIRModule(functionCount: functionCount, symbolCount: symbolCount)
    }
}

public final class LoweringPhase: CompilerPhase {
    public static let name = "Lowerings"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard ctx.kir != nil else {
            throw CompilerPipelineError.invalidInput("KIR not available for lowering.")
        }
    }
}

public final class CodegenPhase: CompilerPhase {
    public static let name = "Codegen"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for codegen.")
        }

        let outputURL = URL(fileURLWithPath: outputPath(from: ctx))
        let content = """
        // KSwiftK synthetic output
        module: \(ctx.options.moduleName)
        mode: \(ctx.options.emit)
        functionCount: \(kir.functionCount)
        """
        do {
            try content.data(using: .utf8)?.write(to: outputURL)
        } catch {
            throw CompilerPipelineError.outputUnavailable
        }
    }

    private func outputPath(from ctx: CompilationContext) -> String {
        switch ctx.options.emit {
        case .executable:
            return ctx.options.outputPath
        case .object:
            return outputPath(base: ctx.options.outputPath, defaultExtension: "o")
        case .llvmIR:
            return outputPath(base: ctx.options.outputPath, defaultExtension: "ll")
        case .kirDump:
            return outputPath(base: ctx.options.outputPath, defaultExtension: "kir")
        case .library:
            return outputPath(base: ctx.options.outputPath, defaultExtension: "a")
        }
    }

    private func outputPath(base: String, defaultExtension: String) -> String {
        let fileURL = URL(fileURLWithPath: base)
        if fileURL.pathExtension.isEmpty {
            return fileURL.appendingPathExtension(defaultExtension).path
        }
        return base
    }
}

public final class LinkPhase: CompilerPhase {
    public static let name = "Link"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        if ctx.options.emit != .executable {
            return
        }
        let outputURL = URL(fileURLWithPath: ctx.options.outputPath)
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompilerPipelineError.outputUnavailable
        }
    }
}
