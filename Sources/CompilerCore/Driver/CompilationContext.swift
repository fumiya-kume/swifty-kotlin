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
}
