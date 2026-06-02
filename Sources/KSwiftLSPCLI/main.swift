import Foundation
import LSPServer

/// Entry point for the `kswift-lsp` language server. Communicates with the
/// editor over stdio using the LSP base protocol. Diagnostic logging goes to
/// stderr so it never corrupts the protocol stream on stdout.
let connection = JSONRPCConnection(
    input: StandardInputStream(),
    output: StandardOutputStream()
)

let server = Server(connection: connection) { message in
    FileHandle.standardError.write(Data("[kswift-lsp] \(message)\n".utf8))
}

let exitCode = server.run()
exit(exitCode)
