@testable import CompilerCore
import Foundation
import XCTest

final class VisibilityAccessControlTests: XCTestCase {
    func testPublicFunctionAccessibleWithinSameFile() throws {
        let source = """
        package test
        public fun greet(): Int = 1
        fun main(): Int = greet()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "VisPub")
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0040", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0041", in: ctx)
        }
    }

    func testInternalFunctionAccessibleWithinSameFile() throws {
        let source = """
        package test
        internal fun helper(): Int = 1
        fun main(): Int = helper()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "VisInternal")
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0040", in: ctx)
        }
    }

    func testPrivateFunctionAccessibleWithinSameFile() throws {
        let source = """
        package test
        private fun secret(): Int = 42
        fun main(): Int = secret()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "VisPrivSame")
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0040", in: ctx)
        }
    }

    func testPrivatePropertyAccessibleWithinSameFile() throws {
        let source = """
        package test
        private val secretVal: Int = 99
        fun main(): Int = secretVal
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "VisPrivPropSame")
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0040", in: ctx)
        }
    }

    private func defineSymbol(
        _ symbols: SymbolTable,
        interner: StringInterner,
        kind: SymbolKind,
        name: String,
        visibility: Visibility,
        file: FileID = FileID(rawValue: 0)
    ) -> SymbolID {
        let interned = interner.intern(name)
        return symbols.define(
            kind: kind,
            name: interned,
            fqName: [interned],
            declSite: makeRange(file: file),
            visibility: visibility,
            flags: []
        )
    }

    func testVisibilityCheckerPublicAlwaysAccessible() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "pubFn", visibility: .public)
        let symbol = try XCTUnwrap(symbols.symbol(sym))
        XCTAssertTrue(checker.isAccessible(symbol, fromFile: FileID(rawValue: 1), enclosingClass: nil))
    }

    func testVisibilityCheckerInternalAlwaysAccessible() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "intFn", visibility: .internal)
        let symbol = try XCTUnwrap(symbols.symbol(sym))
        XCTAssertTrue(checker.isAccessible(symbol, fromFile: FileID(rawValue: 1), enclosingClass: nil))
    }

    func testVisibilityCheckerPrivateSameFile() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "privFn", visibility: .private, file: FileID(rawValue: 0))
        let symbol = try XCTUnwrap(symbols.symbol(sym))
        XCTAssertTrue(checker.isAccessible(symbol, fromFile: FileID(rawValue: 0), enclosingClass: nil))
    }

    func testVisibilityCheckerPrivateDifferentFile() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "privFn2", visibility: .private, file: FileID(rawValue: 0))
        let symbol = try XCTUnwrap(symbols.symbol(sym))
        XCTAssertFalse(checker.isAccessible(symbol, fromFile: FileID(rawValue: 1), enclosingClass: nil))
    }

    func testVisibilityCheckerProtectedInSameClass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "MyClass", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "protMethod", visibility: .protected)
        symbols.setParentSymbol(classSym, for: memberSym)
        let member = try XCTUnwrap(symbols.symbol(memberSym))
        XCTAssertTrue(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: classSym))
    }

    func testVisibilityCheckerProtectedOutsideClass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "MyClass2", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "protMethod2", visibility: .protected)
        symbols.setParentSymbol(classSym, for: memberSym)
        let member = try XCTUnwrap(symbols.symbol(memberSym))
        XCTAssertFalse(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: nil))
    }

    func testVisibilityCheckerProtectedInSubclass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let baseSym = defineSymbol(symbols, interner: interner, kind: .class, name: "Base", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "protSubMethod", visibility: .protected)
        symbols.setParentSymbol(baseSym, for: memberSym)
        let childSym = defineSymbol(symbols, interner: interner, kind: .class, name: "Child", visibility: .public)
        symbols.setDirectSupertypes([baseSym], for: childSym)
        let member = try XCTUnwrap(symbols.symbol(memberSym))
        XCTAssertTrue(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: childSym))
    }

    func testVisibilityCheckerPrivateMemberInSameClass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "PrivClass", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "privMethod", visibility: .private)
        symbols.setParentSymbol(classSym, for: memberSym)
        let member = try XCTUnwrap(symbols.symbol(memberSym))
        XCTAssertTrue(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: classSym))
    }

    func testVisibilityCheckerPrivateMemberOutsideClass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "OwnerClass", visibility: .public)
        let otherClassSym = defineSymbol(symbols, interner: interner, kind: .class, name: "OtherClass", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "privMethod2", visibility: .private)
        symbols.setParentSymbol(classSym, for: memberSym)
        let member = try XCTUnwrap(symbols.symbol(memberSym))
        XCTAssertFalse(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: otherClassSym))
    }
}
