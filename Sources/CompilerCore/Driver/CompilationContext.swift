/// Per-file intermediate representation produced by frontend phases.
/// Each `FileIR` holds the tokens, CST, and AST results for a single
/// source file, enabling file-level parallel processing.
public struct FileIR {
    public let fileID: FileID
    public var tokens: [Token]
    public var syntaxArena: SyntaxArena?
    public var syntaxRoot: NodeID
    public var astFile: ASTFile?
    public var astArena: ASTArena?

    public init(
        fileID: FileID,
        tokens: [Token] = [],
        syntaxArena: SyntaxArena? = nil,
        syntaxRoot: NodeID = NodeID(),
        astFile: ASTFile? = nil,
        astArena: ASTArena? = nil
    ) {
        self.fileID = fileID
        self.tokens = tokens
        self.syntaxArena = syntaxArena
        self.syntaxRoot = syntaxRoot
        self.astFile = astFile
        self.astArena = astArena
    }
}

/// Concurrency model:
/// mutable context fields are written on the main pipeline thread between phases,
/// while parallel phase workers operate on per-phase local data.
public final class CompilationContext: @unchecked Sendable {
    public let options: CompilerOptions
    public let sourceManager: SourceManager
    public let diagnostics: DiagnosticEngine
    public let interner: StringInterner

    public var tokens: [Token] = []
    public var tokensByFile: [(FileID, [Token])] = []
    public var syntaxTree: SyntaxArena? = nil
    public var syntaxTreeRoot: NodeID = NodeID()
    public var syntaxTrees: [(FileID, SyntaxArena, NodeID)] = []
    public var ast: ASTModule? = nil
    public var sema: SemaModule? = nil
    public var kir: KIRModule? = nil
    public var generatedObjectPath: String? = nil
    public var generatedLLVMIRPath: String? = nil

    /// Per-file intermediate representations keyed by FileID.
    /// Populated unconditionally by LexPhase, ParsePhase, and BuildASTPhase
    /// to track per-file tokens, CST, and AST results.
    public var fileIRs: [FileID: FileIR] = [:]

    /// Path to a pre-compiled runtime stub `.o` that should be linked alongside
    /// the user module object when producing an executable.
    public var runtimeStubObjectPath: String? = nil

    /// Incremental compilation cache (non-nil when incremental mode is active).
    public var incrementalCache: IncrementalCompilationCache? = nil

    /// Set of file paths that need recompilation in incremental mode.
    /// `nil` means full build (all files).
    public var incrementalRecompileSet: Set<String>? = nil

    /// Phase timer for recording per-phase wall-clock durations.
    /// Non-nil when the `time-phases` frontend flag is active.
    public var phaseTimer: PhaseTimer? = nil

    public init(
        options: CompilerOptions,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        self.options = options
        self.sourceManager = sourceManager
        self.diagnostics = diagnostics
        self.interner = interner
    }

    /// Returns `true` when incremental compilation is active.
    public var isIncremental: Bool {
        incrementalCache != nil
    }

    /// Returns `true` when the given file path needs recompilation
    /// (always `true` in non-incremental mode).
    public func needsRecompilation(path: String) -> Bool {
        guard let recompileSet = incrementalRecompileSet else {
            return true
        }
        return recompileSet.contains(path)
    }

    /// The number of frontend parallel jobs parsed from `-Xfrontend jobs=N`.
    /// Returns 1 (sequential) if the flag is not set.
    public var frontendJobs: Int {
        options.frontendJobs
    }
}
