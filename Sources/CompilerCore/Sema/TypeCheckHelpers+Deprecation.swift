import Foundation

// ANNO-001: @Deprecated annotation checking helpers.

extension TypeCheckHelpers {
    /// Checks whether `symbol` has a `@Deprecated` annotation and emits an appropriate
    /// diagnostic at `range` (the call/reference site).
    ///
    /// - `@Deprecated("msg")` or `@Deprecated("msg", level = WARNING)` -> warning
    /// - `@Deprecated("msg", level = ERROR)` -> error
    func checkDeprecation(
        for symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let annotations = sema.symbols.annotations(for: symbolID)
        for ann in annotations
            where ann.annotationFQName == "Deprecated"
                || ann.annotationFQName == "kotlin.Deprecated"
        {
            let symbolName = if let sym = sema.symbols.symbol(symbolID) {
                sym.fqName.map { interner.resolve($0) }.joined(separator: ".")
            } else {
                "<unknown>"
            }
            // Extract the deprecation message (first positional argument, if any).
            let message = ann.arguments.first.map { arg in
                arg.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } ?? ""

            // Determine severity from the `level` argument.
            let isError = ann.arguments.contains { arg in
                let normalized = arg.replacingOccurrences(of: " ", with: "")
                return normalized.contains("level=DeprecationLevel.ERROR")
                    || normalized.contains("level=ERROR")
            }

            let deprecationMessage = message.isEmpty
                ? "'\(symbolName)' is deprecated."
                : "'\(symbolName)' is deprecated. \(message)"

            if isError {
                diagnostics.error(
                    "KSWIFTK-SEMA-DEPRECATED",
                    deprecationMessage,
                    range: range
                )
            } else {
                diagnostics.warning(
                    "KSWIFTK-SEMA-DEPRECATED",
                    deprecationMessage,
                    range: range
                )
            }
            return // Only emit one deprecation diagnostic per symbol reference.
        }
    }
}
