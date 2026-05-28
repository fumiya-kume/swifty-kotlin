@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-037: Validates that `kotlin.io.path.Path.useDirectoryEntries(glob, block)`
/// is exposed as an extension function in the `kotlin.io.path` package, type-checks
/// in user source, and is routed to the runtime entry points `kk_path_useDirectoryEntries`
/// (glob overload) and `kk_path_useDirectoryEntries_default` (no-glob overload).
///
/// The extension function is wired through the synthetic Path stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`,
/// and the runtime helpers are declared in `Sources/RuntimeABI/RuntimeABISpec.swift`
/// and implemented in `Sources/Runtime/RuntimePath.swift`.
final class PathUseDirectoryEntriesFunctionTests: XCTestCase {
    func testPathUseDirectoryEntriesExtensionFunctionIsRegisteredInIOPathPackage() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useDirectoryEntries

        fun noop(path: Path) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.useDirectoryEntries extension function in kotlin.io.path should register without errors, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathUseDirectoryEntriesFunctionSignaturesAndRuntimeLinks() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useDirectoryEntries

        fun noop(path: Path) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let pathSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let sequenceSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "sequences", "Sequence"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let sequenceOfPathType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(pathType)],
                nullability: .nonNull
            )))

            let useDirectoryEntriesSymbols = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "useDirectoryEntries"].map(interner.intern)
            )

            let fullUseDirectoryEntries = try XCTUnwrap(useDirectoryEntriesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else { return false }
                let typeParameterType = types.make(.typeParam(TypeParamType(
                    symbol: typeParameterSymbol,
                    nullability: .nonNull
                )))
                let blockType = types.make(.functionType(FunctionType(
                    params: [sequenceOfPathType],
                    returnType: typeParameterType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType, blockType]
                    && signature.returnType == typeParameterType
            })

            let defaultUseDirectoryEntries = try XCTUnwrap(useDirectoryEntriesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else { return false }
                let typeParameterType = types.make(.typeParam(TypeParamType(
                    symbol: typeParameterSymbol,
                    nullability: .nonNull
                )))
                let blockType = types.make(.functionType(FunctionType(
                    params: [sequenceOfPathType],
                    returnType: typeParameterType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [blockType]
                    && signature.returnType == typeParameterType
            })

            XCTAssertEqual(
                symbols.externalLinkName(for: fullUseDirectoryEntries),
                "kk_path_useDirectoryEntries",
                "Path.useDirectoryEntries(glob, block) should bind to runtime helper kk_path_useDirectoryEntries"
            )
            XCTAssertEqual(
                symbols.externalLinkName(for: defaultUseDirectoryEntries),
                "kk_path_useDirectoryEntries_default",
                "Path.useDirectoryEntries(block) should bind to runtime helper kk_path_useDirectoryEntries_default"
            )

            let fullSignature = try XCTUnwrap(symbols.functionSignature(for: fullUseDirectoryEntries))
            XCTAssertEqual(fullSignature.valueParameterHasDefaultValues, [true, false])
            XCTAssertEqual(fullSignature.valueParameterIsVararg, [false, false])
            XCTAssertEqual(fullSignature.typeParameterSymbols.count, 1)

            let defaultSignature = try XCTUnwrap(symbols.functionSignature(for: defaultUseDirectoryEntries))
            XCTAssertEqual(defaultSignature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(defaultSignature.valueParameterIsVararg, [false])
            XCTAssertEqual(defaultSignature.typeParameterSymbols.count, 1)
        }
    }
}
