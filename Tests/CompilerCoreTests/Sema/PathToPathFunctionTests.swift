@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-036: `fun URI.toPath(): Path` in kotlin.io.path.
///
/// Verifies that the synthetic `kotlin.io.path.toPath` extension on
/// `java.net.URI` resolves cleanly and that its external link name targets
/// the runtime export `kk_uri_toPath`.
final class PathToPathFunctionTests: XCTestCase {
    func testUriToPathExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.net.URI
        import kotlin.io.path.Path
        import kotlin.io.path.toPath

        fun convert(uri: URI): Path {
            return uri.toPath()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "URI.toPath() extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let uriSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "net", "URI"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let uriType = types.make(.classType(ClassType(classSymbol: uriSymbol, args: [], nullability: .nonNull)))

            let toPathSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "toPath"].map(interner.intern))
            let toPath = try XCTUnwrap(toPathSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == uriType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: toPath), "kk_uri_toPath")

            let signature = try XCTUnwrap(symbols.functionSignature(for: toPath))
            XCTAssertEqual(signature.receiverType, uriType)
            XCTAssertEqual(signature.returnType, pathType)
            XCTAssertEqual(signature.parameterTypes, [])
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
            XCTAssertEqual(signature.valueParameterIsVararg, [])
            XCTAssertEqual(signature.valueParameterSymbols.count, 0)
        }
    }

    func testUriToPathFunctionLinkNameIsRegistered() throws {
        let source = """
        import java.net.URI
        import kotlin.io.path.toPath

        fun pathOf(uri: URI) = uri.toPath()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected kotlin.io.path.toPath to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "io", "path", "toPath"].map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: fq)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(
                links.contains("kk_uri_toPath"),
                "kotlin.io.path.toPath must link to kk_uri_toPath; got: \(links)"
            )
        }
    }
}
