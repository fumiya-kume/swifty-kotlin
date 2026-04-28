@testable import CompilerCore
import Foundation
import XCTest

final class NativeVector128SurfaceTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    private func symbol(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) }),
            "\(fqPath.joined(separator: ".")) must be registered",
            file: file,
            line: line
        )
    }

    private func classType(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let classSymbol = try symbol(fqPath, sema: sema, interner: interner, file: file, line: line)
        return sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func cinteropVector128Type(
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        try classType(["kotlinx", "cinterop", "Vector128"], sema: sema, interner: interner, file: file, line: line)
    }

    private func memberSignature(
        named name: String,
        parameters: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (SymbolID, FunctionSignature) {
        let ownerSymbol = try symbol(["kotlinx", "cinterop", "Vector128"], sema: sema, interner: interner, file: file, line: line)
        let ownerFQName = try XCTUnwrap(sema.symbols.symbol(ownerSymbol)?.fqName, file: file, line: line)
        let receiver = try cinteropVector128Type(sema: sema, interner: interner, file: file, line: line)
        let candidates = sema.symbols.lookupAll(fqName: ownerFQName + [interner.intern(name)])
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.receiverType == receiver
                && signature.parameterTypes == parameters
                && signature.returnType == returnType
            {
                return (candidate, signature)
            }
        }

        XCTFail("Expected Vector128.\(name) signature, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })", file: file, line: line)
        throw XCTestError(.failureWhileWaiting)
    }

    private func topLevelSignature(
        packagePath: [String],
        named name: String,
        parameters: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (SymbolID, FunctionSignature) {
        let fqName = (packagePath + [name]).map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fqName)
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.receiverType == nil
                && signature.parameterTypes == parameters
                && signature.returnType == returnType
            {
                return (candidate, signature)
            }
        }

        XCTFail("Expected \(packagePath.joined(separator: ".")).\(name) signature, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })", file: file, line: line)
        throw XCTestError(.failureWhileWaiting)
    }

    func testCInteropVector128ClassAndMembersAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let vectorSymbol = try symbol(["kotlinx", "cinterop", "Vector128"], sema: sema, interner: interner)
        let annotations = sema.symbols.annotations(for: vectorSymbol)

        XCTAssertEqual(sema.symbols.symbol(vectorSymbol)?.kind, .class)
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlinx.cinterop.ExperimentalForeignApi" },
            "kotlinx.cinterop.Vector128 must require ExperimentalForeignApi"
        )

        let accessors: [(String, TypeID)] = [
            ("getByteAt", sema.types.intType),
            ("getIntAt", sema.types.intType),
            ("getLongAt", sema.types.longType),
            ("getFloatAt", sema.types.floatType),
            ("getDoubleAt", sema.types.doubleType),
            ("getUByteAt", sema.types.ubyteType),
            ("getUIntAt", sema.types.uintType),
            ("getULongAt", sema.types.ulongType),
        ]
        for (name, returnType) in accessors {
            _ = try memberSignature(
                named: name,
                parameters: [sema.types.intType],
                returnType: returnType,
                sema: sema,
                interner: interner
            )
        }

        let anyNullable = sema.types.makeNullable(sema.types.anyType)
        let (equalsSymbol, _) = try memberSignature(
            named: "equals",
            parameters: [anyNullable],
            returnType: sema.types.booleanType,
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(sema.symbols.symbol(equalsSymbol)?.flags.contains(.operatorFunction) == true)
        _ = try memberSignature(named: "hashCode", parameters: [], returnType: sema.types.intType, sema: sema, interner: interner)
        _ = try memberSignature(named: "toString", parameters: [], returnType: sema.types.stringType, sema: sema, interner: interner)
    }

    func testNativeVector128TypeAliasIsRegisteredWithDeprecationMetadata() throws {
        let (sema, interner) = try makeSema()
        let aliasSymbol = try symbol(["kotlin", "native", "Vector128"], sema: sema, interner: interner)
        let underlyingType = try cinteropVector128Type(sema: sema, interner: interner)
        let annotations = sema.symbols.annotations(for: aliasSymbol)

        XCTAssertEqual(sema.symbols.symbol(aliasSymbol)?.kind, .typeAlias)
        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol), underlyingType)
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.Deprecated" },
            "kotlin.native.Vector128 must carry @Deprecated metadata"
        )
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.DeprecatedSinceKotlin" },
            "kotlin.native.Vector128 must carry @DeprecatedSinceKotlin metadata"
        )
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlinx.cinterop.ExperimentalForeignApi" },
            "kotlin.native.Vector128 must require ExperimentalForeignApi"
        )
    }

    func testVectorOfFactoriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let vectorType = try cinteropVector128Type(sema: sema, interner: interner)

        for packagePath in [["kotlin", "native"], ["kotlinx", "cinterop"]] {
            let (floatFactory, _) = try topLevelSignature(
                packagePath: packagePath,
                named: "vectorOf",
                parameters: [sema.types.floatType, sema.types.floatType, sema.types.floatType, sema.types.floatType],
                returnType: vectorType,
                sema: sema,
                interner: interner
            )
            let (intFactory, _) = try topLevelSignature(
                packagePath: packagePath,
                named: "vectorOf",
                parameters: [sema.types.intType, sema.types.intType, sema.types.intType, sema.types.intType],
                returnType: vectorType,
                sema: sema,
                interner: interner
            )
            let floatAnnotations = sema.symbols.annotations(for: floatFactory)
            let intAnnotations = sema.symbols.annotations(for: intFactory)
            XCTAssertTrue(floatAnnotations.contains { $0.annotationFQName == "kotlinx.cinterop.ExperimentalForeignApi" })
            XCTAssertTrue(intAnnotations.contains { $0.annotationFQName == "kotlinx.cinterop.ExperimentalForeignApi" })
            if packagePath == ["kotlin", "native"] {
                XCTAssertTrue(floatAnnotations.contains { $0.annotationFQName == "kotlin.Deprecated" })
                XCTAssertTrue(intAnnotations.contains { $0.annotationFQName == "kotlin.DeprecatedSinceKotlin" })
            }
        }
    }

    func testVector128SurfaceResolvesInSource() {
        let source = """
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlin.native.Vector128
        import kotlin.native.vectorOf

        fun probe(vector: Vector128): Int {
            val ints = vectorOf(1, 2, 3, 4)
            val floats = vectorOf(1.0f, 2.0f, 3.0f, 4.0f)
            return vector.getIntAt(0) + ints.getIntAt(1) + floats.getIntAt(2)
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected Vector128 source to resolve without errors, got \(errors)")
    }
}
