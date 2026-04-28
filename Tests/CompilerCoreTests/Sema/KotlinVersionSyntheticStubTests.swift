@testable import CompilerCore
import XCTest

final class KotlinVersionSyntheticStubTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKotlinVersionConstructorsAndPropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let versionFQName = ["kotlin", "KotlinVersion"].map { interner.intern($0) }
        let versionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: versionFQName))
        XCTAssertEqual(sema.symbols.symbol(versionSymbol)?.kind, .class)

        let versionType = sema.types.make(.classType(ClassType(
            classSymbol: versionSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructorFQName = versionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let twoArgumentConstructor = try XCTUnwrap(constructors.first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [sema.types.intType, sema.types.intType]
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: twoArgumentConstructor), "kk_kotlin_version_new")
        XCTAssertEqual(sema.symbols.functionSignature(for: twoArgumentConstructor)?.returnType, versionType)

        let threeArgumentConstructor = try XCTUnwrap(constructors.first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [
                sema.types.intType,
                sema.types.intType,
                sema.types.intType,
            ]
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: threeArgumentConstructor), "kk_kotlin_version_new_patch")
        XCTAssertEqual(sema.symbols.functionSignature(for: threeArgumentConstructor)?.returnType, versionType)

        let expectedProperties: [(name: String, link: String)] = [
            ("major", "kk_kotlin_version_major"),
            ("minor", "kk_kotlin_version_minor"),
            ("patch", "kk_kotlin_version_patch"),
        ]
        for expected in expectedProperties {
            let propertySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: versionFQName + [interner.intern(expected.name)]))
            XCTAssertEqual(sema.symbols.symbol(propertySymbol)?.kind, .property)
            XCTAssertEqual(sema.symbols.parentSymbol(for: propertySymbol), versionSymbol)
            XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), sema.types.intType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), expected.link)
        }
    }

    func testKotlinVersionConstructorsAndPropertiesResolveInSource() throws {
        _ = try makeSema(source: """
        fun defaultPatch(): Int = KotlinVersion(2, 1).patch
        fun explicitPatch(): Int = KotlinVersion(2, 1, 20).major
        fun typed(): KotlinVersion = KotlinVersion(1, 9)
        """)
    }
}
