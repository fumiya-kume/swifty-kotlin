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

        let comparableFQName = ["kotlin", "Comparable"].map { interner.intern($0) }
        let comparableSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: comparableFQName))
        XCTAssertTrue(sema.symbols.directSupertypes(for: versionSymbol).contains(comparableSymbol))
        XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: versionSymbol, supertype: comparableSymbol), [.in(versionType)])

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

        let companionFQName = versionFQName + [interner.intern("Companion")]
        let companionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: companionFQName))
        XCTAssertEqual(sema.symbols.companionObjectSymbol(for: versionSymbol), companionSymbol)

        let currentSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: companionFQName + [interner.intern("CURRENT")]))
        XCTAssertEqual(sema.symbols.symbol(currentSymbol)?.kind, .property)
        XCTAssertEqual(sema.symbols.parentSymbol(for: currentSymbol), companionSymbol)
        XCTAssertEqual(sema.symbols.propertyType(for: currentSymbol), versionType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: currentSymbol), "kk_kotlin_version_current")
        XCTAssertTrue(sema.symbols.symbol(currentSymbol)?.flags.contains(.static) == true)

        let compareToSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: versionFQName + [interner.intern("compareTo")]).first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [versionType]
        })
        XCTAssertEqual(sema.symbols.functionSignature(for: compareToSymbol)?.receiverType, versionType)
        XCTAssertEqual(sema.symbols.functionSignature(for: compareToSymbol)?.returnType, sema.types.intType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: compareToSymbol), "kk_kotlin_version_compareTo")
        XCTAssertTrue(sema.symbols.symbol(compareToSymbol)?.flags.contains(.operatorFunction) == true)

        let isAtLeastFQName = versionFQName + [interner.intern("isAtLeast")]
        let twoArgumentIsAtLeast = try XCTUnwrap(sema.symbols.lookupAll(fqName: isAtLeastFQName).first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [sema.types.intType, sema.types.intType]
        })
        XCTAssertEqual(sema.symbols.functionSignature(for: twoArgumentIsAtLeast)?.receiverType, versionType)
        XCTAssertEqual(sema.symbols.functionSignature(for: twoArgumentIsAtLeast)?.returnType, sema.types.booleanType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: twoArgumentIsAtLeast), "kk_kotlin_version_isAtLeast")

        let threeArgumentIsAtLeast = try XCTUnwrap(sema.symbols.lookupAll(fqName: isAtLeastFQName).first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [
                sema.types.intType,
                sema.types.intType,
                sema.types.intType,
            ]
        })
        XCTAssertEqual(sema.symbols.functionSignature(for: threeArgumentIsAtLeast)?.receiverType, versionType)
        XCTAssertEqual(sema.symbols.functionSignature(for: threeArgumentIsAtLeast)?.returnType, sema.types.booleanType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: threeArgumentIsAtLeast), "kk_kotlin_version_isAtLeast_patch")
    }

    func testKotlinVersionConstructorsAndPropertiesResolveInSource() throws {
        _ = try makeSema(source: """
        fun defaultPatch(): Int = KotlinVersion(2, 1).patch
        fun explicitPatch(): Int = KotlinVersion(2, 1, 20).major
        fun typed(): KotlinVersion = KotlinVersion(1, 9)
        fun currentPatch(): Int = KotlinVersion.CURRENT.patch
        fun compare(): Int = KotlinVersion(2, 1, 20).compareTo(KotlinVersion(2, 1))
        fun hasAtLeast(): Boolean = KotlinVersion.CURRENT.isAtLeast(1, 0) && KotlinVersion(2, 1).isAtLeast(2, 1, 0)
        fun ordered(): Boolean = KotlinVersion(2, 1) < KotlinVersion(2, 1, 20)
        """)
    }
}
