import CompilerBackend
import CompilerCore
import Foundation
import LSPServer

/// Entry point for the `kswift-lsp` language server. Communicates with the
/// editor over stdio using the LSP base protocol. Diagnostic logging goes to
/// stderr so it never corrupts the protocol stream on stdout.
let connection = JSONRPCConnection(
    input: StandardInputStream(),
    output: StandardOutputStream()
)

let stdlibLibraryPath: String
do {
    // Resolve or build the artifact once before the LSP event loop starts.
    stdlibLibraryPath = try StdlibArtifactCache.resolveOrBuild(target: TargetTriple.hostDefault())
} catch {
    let message = "KSWIFTK-LIB-0023: Cannot prepare the LSP bundled stdlib artifact: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

let server = Server(
    connection: connection,
    analyzer: Analyzer(stdlibLibraryPath: stdlibLibraryPath)
)

let exitCode = server.run()
exit(exitCode)
