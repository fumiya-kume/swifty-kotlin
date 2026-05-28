@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-011: Validates that `kotlin.io.path.Path.createSymbolicLinkPointingTo(target, vararg attributes)`
/// resolves through Sema for plain Path receivers and returns a `kotlin.io.path.Path` value.
/// The extension function is wired through the synthetic Path stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`, and is
/// expected to bind to the runtime helper `kk_path_createSymbolicLinkPointingTo_attributes`
/// declared in `Sources/RuntimeABI/RuntimeABISpec.swift`.
final class PathCreateSymbolicLinkPointingToFunctionTests: XCTestCase {
    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    func testPathCreateSymbolicLinkPointingToResolvesWithTargetOnly() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.createSymbolicLinkPointingTo

        fun makeLink(link: Path, target: Path): Path {
            return link.createSymbolicLinkPointingTo(target)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.createSymbolicLinkPointingTo(target) should resolve without attributes, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathCreateSymbolicLinkPointingToResolvesWithVarargAttributes() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createSymbolicLinkPointingTo

        fun makeLink(link: Path, target: Path, attr: FileAttribute<*>): Path {
            return link.createSymbolicLinkPointingTo(target, attr)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.createSymbolicLinkPointingTo(target, attr) should resolve with vararg FileAttribute args, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathCreateSymbolicLinkPointingToFunctionSignatureAndRuntimeLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let pathSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let fileAttributeSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let fileAttributeStarType = types.make(
                .classType(ClassType(classSymbol: fileAttributeSymbol, args: [.star], nullability: .nonNull))
            )

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "createSymbolicLinkPointingTo"].map(interner.intern)
            )
            let createSymLink = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, fileAttributeStarType]
                    && signature.returnType == pathType
            })

            XCTAssertEqual(
                symbols.externalLinkName(for: createSymLink),
                "kk_path_createSymbolicLinkPointingTo_attributes",
                "Path.createSymbolicLinkPointingTo should bind to runtime helper kk_path_createSymbolicLinkPointingTo_attributes"
            )

            let signature = try XCTUnwrap(symbols.functionSignature(for: createSymLink))
            XCTAssertEqual(signature.valueParameterIsVararg, [false, true])
            XCTAssertEqual(signature.returnType, pathType)
            XCTAssertEqual(signature.receiverType, pathType)
        }
    }

    func testPathCreateSymbolicLinkPointingToCallExpressionTypedAsPath() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createSymbolicLinkPointingTo

        fun makeLinks(link: Path, target: Path, attr: FileAttribute<*>): Path {
            val noAttrs = link.createSymbolicLinkPointingTo(target)
            val withAttr = link.createSymbolicLinkPointingTo(target, attr)
            return withAttr
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.createSymbolicLinkPointingTo() should resolve cleanly: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "createSymbolicLinkPointingTo", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    pathType,
                    "Each Path.createSymbolicLinkPointingTo() call expression must be typed as kotlin.io.path.Path"
                )
            }
        }
    }
}
