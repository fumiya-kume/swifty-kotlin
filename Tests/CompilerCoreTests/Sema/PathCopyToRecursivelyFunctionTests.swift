@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-010: Validates that `kotlin.io.path.Path.copyToRecursively(...)` resolves
/// through Sema for both overload shapes:
///   - `copyToRecursively(target, onError, followLinks, overwrite): Path`  → kk_path_copyToRecursively_overwrite
///   - `copyToRecursively(target, onError, followLinks, copyAction): Path` → kk_path_copyToRecursively_copyAction
///
/// The extension functions are wired through the synthetic Path stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`, and are
/// expected to bind to the runtime helpers declared in
/// `Sources/RuntimeABI/RuntimeABISpec.swift`.
final class PathCopyToRecursivelyFunctionTests: XCTestCase {
    // MARK: - overwrite overload

    func testPathCopyToRecursivelyOverwriteResolvesWithAllArguments() throws {
        let source = """
        import kotlin.Exception
        import kotlin.io.path.OnErrorResult
        import kotlin.io.path.Path
        import kotlin.io.path.copyToRecursively

        fun copyTree(source: Path, target: Path, onError: (Path, Path, Exception) -> OnErrorResult): Path {
            return source.copyToRecursively(target, onError, true, true)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.copyToRecursively(target, onError, followLinks, overwrite) should resolve without errors, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathCopyToRecursivelyOverwriteSignatureAndRuntimeLink() throws {
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
            let exceptionSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "Exception"].map(interner.intern))
            )
            let onErrorResultSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "OnErrorResult"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let exceptionType = types.make(
                .classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull))
            )
            let onErrorResultType = types.make(
                .classType(ClassType(classSymbol: onErrorResultSymbol, args: [], nullability: .nonNull))
            )
            let onErrorType = types.make(.functionType(FunctionType(
                params: [pathType, pathType, exceptionType],
                returnType: onErrorResultType,
                isSuspend: false,
                nullability: .nonNull
            )))

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern)
            )
            let overwriteOverload = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, onErrorType, types.booleanType, types.booleanType]
                    && signature.returnType == pathType
            }, "overwrite overload of copyToRecursively must be registered")

            XCTAssertEqual(
                symbols.externalLinkName(for: overwriteOverload),
                "kk_path_copyToRecursively_overwrite",
                "overwrite overload must bind to kk_path_copyToRecursively_overwrite"
            )

            let signature = try XCTUnwrap(symbols.functionSignature(for: overwriteOverload))
            XCTAssertEqual(signature.receiverType, pathType)
            XCTAssertEqual(signature.returnType, pathType)
            XCTAssertEqual(signature.parameterTypes.count, 4)
        }
    }

    // MARK: - copyAction overload

    func testPathCopyToRecursivelyCopyActionResolvesWithAllArguments() throws {
        let source = """
        import kotlin.Exception
        import kotlin.io.path.CopyActionContext
        import kotlin.io.path.CopyActionResult
        import kotlin.io.path.OnErrorResult
        import kotlin.io.path.Path
        import kotlin.io.path.copyToRecursively

        fun copyTree(
            source: Path,
            target: Path,
            onError: (Path, Path, Exception) -> OnErrorResult,
            copyAction: CopyActionContext.(Path, Path) -> CopyActionResult
        ): Path {
            return source.copyToRecursively(target, onError, true, copyAction)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.copyToRecursively(target, onError, followLinks, copyAction) should resolve without errors, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathCopyToRecursivelyCopyActionSignatureAndRuntimeLink() throws {
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
            let exceptionSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "Exception"].map(interner.intern))
            )
            let onErrorResultSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "OnErrorResult"].map(interner.intern))
            )
            let copyActionContextSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "CopyActionContext"].map(interner.intern))
            )
            let copyActionResultSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "CopyActionResult"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let exceptionType = types.make(
                .classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull))
            )
            let onErrorResultType = types.make(
                .classType(ClassType(classSymbol: onErrorResultSymbol, args: [], nullability: .nonNull))
            )
            let copyActionContextType = types.make(
                .classType(ClassType(classSymbol: copyActionContextSymbol, args: [], nullability: .nonNull))
            )
            let copyActionResultType = types.make(
                .classType(ClassType(classSymbol: copyActionResultSymbol, args: [], nullability: .nonNull))
            )
            let onErrorType = types.make(.functionType(FunctionType(
                params: [pathType, pathType, exceptionType],
                returnType: onErrorResultType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let copyActionType = types.make(.functionType(FunctionType(
                receiver: copyActionContextType,
                params: [pathType, pathType],
                returnType: copyActionResultType,
                isSuspend: false,
                nullability: .nonNull
            )))

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern)
            )
            let copyActionOverload = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, onErrorType, types.booleanType, copyActionType]
                    && signature.returnType == pathType
            }, "copyAction overload of copyToRecursively must be registered")

            XCTAssertEqual(
                symbols.externalLinkName(for: copyActionOverload),
                "kk_path_copyToRecursively_copyAction",
                "copyAction overload must bind to kk_path_copyToRecursively_copyAction"
            )

            let signature = try XCTUnwrap(symbols.functionSignature(for: copyActionOverload))
            XCTAssertEqual(signature.receiverType, pathType)
            XCTAssertEqual(signature.returnType, pathType)
            XCTAssertEqual(signature.parameterTypes.count, 4)
        }
    }

    // MARK: - both overloads registered

    func testBothCopyToRecursivelyOverloadsAreRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern)
            )
            XCTAssertGreaterThanOrEqual(
                candidates.count,
                2,
                "At least two copyToRecursively overloads (overwrite and copyAction) must be registered"
            )

            let linkNames = Set(candidates.compactMap { symbols.externalLinkName(for: $0) })
            XCTAssertTrue(
                linkNames.contains("kk_path_copyToRecursively_overwrite"),
                "overwrite overload must be present"
            )
            XCTAssertTrue(
                linkNames.contains("kk_path_copyToRecursively_copyAction"),
                "copyAction overload must be present"
            )
        }
    }
}
