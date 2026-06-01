@testable import CompilerCore
import XCTest

/// STDLIB-IO-PROP-004: Validates that the synthetic `kotlin.io.File.isRooted`
/// extension property is registered with the `java.io.File` receiver and is
/// resolvable in Sema with a `Boolean` result type. The runtime link is
/// `kk_file_isRooted` (see `Sources/Runtime/RuntimeFileIO.swift`).
final class FileIsRootedTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected File.isRooted to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    /// The extension property symbol lives under `kotlin.io.isRooted` with
    /// `java.io.File` as its receiver type and `Boolean` as its return type.
    /// The accessor getter must share the same external link name so codegen
    /// can dispatch the property read through `kk_file_isRooted`.
    func testFileIsRootedExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinIOPkg = ["kotlin", "io"].map { interner.intern($0) }
        let javaIOPkg = ["java", "io"].map { interner.intern($0) }
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: javaIOPkg + [interner.intern("File")]
        ))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: kotlinIOPkg + [interner.intern("isRooted")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) == fileType
            },
            "Expected kotlin.io.File.isRooted extension property"
        )
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), boolType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_file_isRooted")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_file_isRooted")
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(signature.receiverType, fileType)
        XCTAssertEqual(signature.returnType, boolType)
        XCTAssertTrue(signature.parameterTypes.isEmpty)
    }

    /// User code that reads `file.isRooted` should type-check without errors
    /// and the surrounding function should still infer `Boolean`. The branch
    /// usage mirrors typical stdlib call sites where `isRooted` gates further
    /// path manipulation.
    func testFileIsRootedResolvesInSource() throws {
        let source = """
        import java.io.File

        fun checkRoot(file: File): Boolean {
            return file.isRooted
        }

        fun useInBranch(file: File): String {
            return if (file.isRooted) "abs" else "rel"
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let checkRootSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("checkRoot")]))
        let checkSignature = try XCTUnwrap(sema.symbols.functionSignature(for: checkRootSymbol))
        XCTAssertEqual(
            checkSignature.returnType,
            sema.types.make(.primitive(.boolean, .nonNull)),
            "checkRoot should still return Boolean once isRooted resolves"
        )

        let useInBranchSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("useInBranch")])
        )
        let branchSignature = try XCTUnwrap(sema.symbols.functionSignature(for: useInBranchSymbol))
        XCTAssertEqual(
            branchSignature.returnType,
            sema.types.stringType,
            "useInBranch should still return String once isRooted resolves"
        )
    }
}
