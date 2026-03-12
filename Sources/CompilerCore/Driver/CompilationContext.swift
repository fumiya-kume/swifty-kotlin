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
    public lazy var builtinNames: BuiltinTypeNames = BuiltinTypeNames(interner: interner)

    public internal(set) var tokens: [Token] = []
    public internal(set) var tokensByFile: [(FileID, [Token])] = []
    public internal(set) var syntaxTree: SyntaxArena?
    public internal(set) var syntaxTreeRoot: NodeID = .init()
    public internal(set) var syntaxTrees: [(FileID, SyntaxArena, NodeID)] = []
    public internal(set) var ast: ASTModule?
    public internal(set) var sema: SemaModule?
    public internal(set) var kir: KIRModule?
    public internal(set) var generatedObjectPath: String?
    public internal(set) var generatedLLVMIRPath: String?

    /// Per-file intermediate representations keyed by FileID.
    /// Populated unconditionally by LexPhase, ParsePhase, and BuildASTPhase
    /// to track per-file tokens, CST, and AST results.
    public internal(set) var fileIRs: [FileID: FileIR] = [:]

    /// Incremental compilation cache (non-nil when incremental mode is active).
    public internal(set) var incrementalCache: IncrementalCompilationCache?

    /// Set of file paths that need recompilation in incremental mode.
    /// `nil` means full build (all files).
    public internal(set) var incrementalRecompileSet: Set<String>?

    /// Phase timer for recording per-phase wall-clock durations.
    /// Non-nil when the `time-phases` frontend flag is active.
    public internal(set) var phaseTimer: PhaseTimer?

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

    public func storeLexResults(allTokens: [Token], tokensByFile: [(FileID, [Token])]) {
        tokens = allTokens
        self.tokensByFile = tokensByFile
    }

    public func storeSyntaxTrees(_ syntaxTrees: [(FileID, SyntaxArena, NodeID)]) {
        self.syntaxTrees = syntaxTrees
        if let first = syntaxTrees.first {
            syntaxTree = first.1
            syntaxTreeRoot = first.2
        } else {
            syntaxTree = nil
            syntaxTreeRoot = .init()
        }
    }

    public func storeFallbackSyntaxTree(fileID: FileID, arena: SyntaxArena, root: NodeID) {
        syntaxTree = arena
        syntaxTreeRoot = root
        syntaxTrees = [(fileID, arena, root)]
    }

    public func updateFileIR(fileID: FileID, _ update: (inout FileIR) -> Void) {
        var fileIR = fileIRs[fileID] ?? FileIR(fileID: fileID)
        update(&fileIR)
        fileIRs[fileID] = fileIR
    }

    public func storeAST(_ ast: ASTModule) {
        self.ast = ast
    }

    public func storeSema(_ sema: SemaModule) {
        self.sema = sema
    }

    public func storeKIR(_ kir: KIRModule) {
        self.kir = kir
    }

    public func storeGeneratedObjectPath(_ path: String) {
        generatedObjectPath = path
    }

    public func storeGeneratedLLVMIRPath(_ path: String) {
        generatedLLVMIRPath = path
    }

    public func installIncrementalCache(_ cache: IncrementalCompilationCache) {
        incrementalCache = cache
    }

    public func setIncrementalRecompileSet(_ recompileSet: Set<String>?) {
        incrementalRecompileSet = recompileSet
    }

    public func installPhaseTimer(_ timer: PhaseTimer) {
        phaseTimer = timer
    }
}
