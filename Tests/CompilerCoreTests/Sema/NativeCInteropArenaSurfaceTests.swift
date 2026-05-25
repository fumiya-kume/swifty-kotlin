@testable import CompilerCore
import Foundation
import XCTest

final class NativeCInteropArenaSurfaceTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected C interop Arena surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
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

    private func arenaMemberSignature(
        named name: String,
        parameters: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (SymbolID, FunctionSignature) {
        let arenaSymbol = try symbol(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner, file: file, line: line)
        let ownerFQName = try XCTUnwrap(sema.symbols.symbol(arenaSymbol)?.fqName, file: file, line: line)
        let receiver = try classType(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner, file: file, line: line)
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

        XCTFail("Expected Arena.\(name) signature, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })", file: file, line: line)
        throw XCTestError(.failureWhileWaiting)
    }

    func testArenaClassAndRequiredSupportSymbolsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let arenaSymbol = try symbol(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner)
        let arenaBaseSymbol = try symbol(["kotlinx", "cinterop", "ArenaBase"], sema: sema, interner: interner)
        let nativeFreeablePlacementSymbol = try symbol(["kotlinx", "cinterop", "NativeFreeablePlacement"], sema: sema, interner: interner)
        let nativePlacementSymbol = try symbol(["kotlinx", "cinterop", "NativePlacement"], sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(arenaSymbol)?.kind, .class)
        XCTAssertEqual(sema.symbols.symbol(arenaBaseSymbol)?.kind, .class)
        XCTAssertEqual(sema.symbols.symbol(nativeFreeablePlacementSymbol)?.kind, .interface)
        XCTAssertEqual(sema.symbols.directSupertypes(for: arenaSymbol), [arenaBaseSymbol])
        XCTAssertEqual(sema.symbols.directSupertypes(for: nativeFreeablePlacementSymbol), [nativePlacementSymbol])
    }

    func testArenaConstructorUsesNativeFreeablePlacementDefault() throws {
        let (sema, interner) = try makeSema()
        let arenaSymbol = try symbol(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner)
        let arenaFQName = try XCTUnwrap(sema.symbols.symbol(arenaSymbol)?.fqName)
        let arenaType = try classType(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner)
        let parentType = try classType(["kotlinx", "cinterop", "NativeFreeablePlacement"], sema: sema, interner: interner)
        let constructors = sema.symbols.lookupAll(fqName: arenaFQName + [interner.intern("<init>")])

        let signature = try XCTUnwrap(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [parentType] && $0.returnType == arenaType
        })
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [true])
    }

    func testArenaAllocOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let nativePointedType = try classType(["kotlinx", "cinterop", "NativePointed"], sema: sema, interner: interner)

        let (longAlloc, _) = try arenaMemberSignature(
            named: "alloc",
            parameters: [sema.types.longType, sema.types.intType],
            returnType: nativePointedType,
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(sema.symbols.symbol(longAlloc)?.flags.contains(.overrideMember) == true)

        let (intAlloc, _) = try arenaMemberSignature(
            named: "alloc",
            parameters: [sema.types.intType, sema.types.intType],
            returnType: nativePointedType,
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(sema.symbols.symbol(intAlloc)?.flags.contains(.openType) == true)
    }

    func testArenaResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.Arena
        import kotlinx.cinterop.NativePointed

        fun probe(): NativePointed {
            val arena = Arena()
            return arena.alloc(8, 4)
        }
        """)
    }
}
