import Foundation

public struct IncrementalFrontendState: Codable {
    public static let supportedVersion = 1

    public let version: Int
    public let buildConfigurationHash: String
    public let internerValues: [String]
    public let files: [ASTFile]
    public let arenaSnapshot: ASTArenaSnapshot
    public let activeDeclsByFileRawID: [Int32: [DeclID]]
    public let tokenCountsByFileRawID: [Int32: Int]
    public let declarationCount: Int
    public let tokenCount: Int

    public init(
        buildConfigurationHash: String,
        internerValues: [String],
        files: [ASTFile],
        arenaSnapshot: ASTArenaSnapshot,
        activeDeclsByFileRawID: [Int32: [DeclID]],
        tokenCountsByFileRawID: [Int32: Int],
        declarationCount: Int,
        tokenCount: Int
    ) {
        version = Self.supportedVersion
        self.buildConfigurationHash = buildConfigurationHash
        self.internerValues = internerValues
        self.files = files
        self.arenaSnapshot = arenaSnapshot
        self.activeDeclsByFileRawID = activeDeclsByFileRawID
        self.tokenCountsByFileRawID = tokenCountsByFileRawID
        self.declarationCount = declarationCount
        self.tokenCount = tokenCount
    }

    public init?(context ctx: CompilationContext, buildConfigurationHash: String) {
        guard let ast = ctx.ast else {
            return nil
        }
        var tokenCountsByFileRawID = ctx.incrementalFrontendState?.tokenCountsByFileRawID ?? [:]
        for (fileID, tokens) in ctx.tokensByFile {
            tokenCountsByFileRawID[fileID.rawValue] = tokens.count
        }
        self.init(
            buildConfigurationHash: buildConfigurationHash,
            internerValues: ctx.interner.snapshotValues(),
            files: ast.files,
            arenaSnapshot: ast.arena.snapshot(),
            activeDeclsByFileRawID: ast.activeDeclsByFileRawID,
            tokenCountsByFileRawID: tokenCountsByFileRawID,
            declarationCount: ast.declarationCount,
            tokenCount: ast.tokenCount
        )
    }
}
