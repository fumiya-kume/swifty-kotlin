import Foundation

public protocol CompilerPhase {
    static var name: String { get }
    func run(_ ctx: CompilationContext) throws
}

enum CompilerPipelineError: Error {
    case loadError
    case invalidInput(String)
    case outputUnavailable
}
