import Foundation

enum GoldenHarnessGoldenSuite: String, CaseIterable, Sendable {
    case lexer = "Lexer"
    case parser = "Parser"
    case sema = "Sema"
    case diagnostics = "Diagnostics"
}
