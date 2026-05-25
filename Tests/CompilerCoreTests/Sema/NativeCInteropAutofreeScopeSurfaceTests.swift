@testable import CompilerCore
import Foundation
import XCTest

final class NativeCInteropAutofreeScopeSurfaceTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected C interop AutofreeScope surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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

    private func autofreeScopeMemberSignature(
        named name: String,
        parameters: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (SymbolID, FunctionSignature) {
        let autofreeScopeSymbol = try symbol(["kotlinx", "cinterop", "AutofreeScope"], sema: sema, interner: interner, file: file, line: line)
        let ownerFQName = try XCTUnwrap(sema.symbols.symbol(autofreeScopeSymbol)?.fqName, file: file, line: line)
        let receiver = try classType(["kotlinx", "cinterop", "AutofreeScope"], sema: sema, interner: interner, file: file, line: line)
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

        XCTFail("Expected AutofreeScope.\(name) signature, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })", file: file, line: line)
        throw XCTestError(.failureWhileWaiting)
    }

    func testAutofreeScopeClassAndSupportSymbolsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let autofreeScopeSymbol = try symbol(["kotlinx", "cinterop", "AutofreeScope"], sema: sema, interner: interner)
        let deferScopeSymbol = try symbol(["kotlinx", "cinterop", "DeferScope"], sema: sema, interner: interner)
        let nativePlacementSymbol = try symbol(["kotlinx", "cinterop", "NativePlacement"], sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(autofreeScopeSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(autofreeScopeSymbol)?.flags.contains(.abstractType) == true)
        XCTAssertEqual(sema.symbols.symbol(deferScopeSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(deferScopeSymbol)?.flags.contains(.openType) == true)
        XCTAssertEqual(sema.symbols.directSupertypes(for: autofreeScopeSymbol), [deferScopeSymbol, nativePlacementSymbol])
    }

    func testAutofreeScopeConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let autofreeScopeSymbol = try symbol(["kotlinx", "cinterop", "AutofreeScope"], sema: sema, interner: interner)
        let autofreeScopeFQName = try XCTUnwrap(sema.symbols.symbol(autofreeScopeSymbol)?.fqName)
        let autofreeScopeType = try classType(["kotlinx", "cinterop", "AutofreeScope"], sema: sema, interner: interner)
        let constructors = sema.symbols.lookupAll(fqName: autofreeScopeFQName + [interner.intern("<init>")])

        let signature = try XCTUnwrap(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes.isEmpty && $0.returnType == autofreeScopeType
        })
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
    }

    func testAutofreeScopeAllocOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let nativePointedType = try classType(["kotlinx", "cinterop", "NativePointed"], sema: sema, interner: interner)

        let (longAlloc, _) = try autofreeScopeMemberSignature(
            named: "alloc",
            parameters: [sema.types.longType, sema.types.intType],
            returnType: nativePointedType,
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(sema.symbols.symbol(longAlloc)?.flags.isSuperset(of: [.abstractType, .overrideMember]) == true)

        let (intAlloc, _) = try autofreeScopeMemberSignature(
            named: "alloc",
            parameters: [sema.types.intType, sema.types.intType],
            returnType: nativePointedType,
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(sema.symbols.symbol(intAlloc)?.flags.contains(.openType) == true)
    }

    func testAutofreeScopeResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.AutofreeScope
        import kotlinx.cinterop.NativePointed

        fun probeInt(scope: AutofreeScope): NativePointed {
            return scope.alloc(8, 4)
        }

        fun probeLong(scope: AutofreeScope): NativePointed {
            return scope.alloc(8L, 4)
        }
        """)
    }
}
