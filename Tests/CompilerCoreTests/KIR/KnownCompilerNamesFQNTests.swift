#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Regression tests for KnownCompilerNames FQN-based symbol matching.
/// Ensures that user-defined types named "Set" or "MutableSet" are not
/// confused with stdlib kotlin.collections.Set / MutableSet.
@Suite
struct KnownCompilerNamesFQNTests {

    // MARK: - isSetLikeSymbol FQN checks

    @Test func testIsSetLikeSymbolMatchesStdlibSetFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        // stdlib Set with correct FQN: kotlin.collections.Set
        let stdlibSetSymbol = symbols.define(
            kind: .typeAlias,
            name: interner.intern("Set"),
            fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Set")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let stdlibSetInfo = symbols.symbol(stdlibSetSymbol)!
        #expect(knownNames.isSetLikeSymbol(stdlibSetInfo),
                      "stdlib Set (kotlin.collections.Set) should be recognized as set-like")
    }

    @Test func testIsSetLikeSymbolMatchesStdlibMutableSetFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        // stdlib MutableSet with correct FQN: kotlin.collections.MutableSet
        let stdlibMutableSetSymbol = symbols.define(
            kind: .typeAlias,
            name: interner.intern("MutableSet"),
            fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("MutableSet")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let stdlibMutableSetInfo = symbols.symbol(stdlibMutableSetSymbol)!
        #expect(knownNames.isSetLikeSymbol(stdlibMutableSetInfo),
                      "stdlib MutableSet (kotlin.collections.MutableSet) should be recognized as set-like")
    }

    @Test func testIsSetLikeSymbolRejectsUserDefinedSetWithNonStdlibFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        // User-defined class named "Set" with a non-stdlib FQN
        let userSetSymbol = symbols.define(
            kind: .class,
            name: interner.intern("Set"),
            fqName: [interner.intern("com"), interner.intern("example"), interner.intern("Set")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let userSetInfo = symbols.symbol(userSetSymbol)!
        #expect(!(knownNames.isSetLikeSymbol(userSetInfo)),
                       "User-defined Set (com.example.Set) must NOT be recognized as stdlib set-like")
    }

    @Test func testIsSetLikeSymbolRejectsUserDefinedMutableSetWithNonStdlibFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        // User-defined class named "MutableSet" with a non-stdlib FQN
        let userMutableSetSymbol = symbols.define(
            kind: .class,
            name: interner.intern("MutableSet"),
            fqName: [interner.intern("com"), interner.intern("mylib"), interner.intern("MutableSet")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let userMutableSetInfo = symbols.symbol(userMutableSetSymbol)!
        #expect(!(knownNames.isSetLikeSymbol(userMutableSetInfo)),
                       "User-defined MutableSet (com.mylib.MutableSet) must NOT be recognized as stdlib set-like")
    }

    @Test func testIsSetLikeSymbolAllowsSyntheticSymbolWithoutFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        // Synthetic symbol with name "Set" but empty FQN (fallback allowed)
        let syntheticSetSymbol = symbols.define(
            kind: .typeAlias,
            name: interner.intern("Set"),
            fqName: [],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let syntheticSetInfo = symbols.symbol(syntheticSetSymbol)!
        #expect(knownNames.isSetLikeSymbol(syntheticSetInfo),
                      "Synthetic Set (no FQN) should still be recognized as set-like via fallback")
    }

    // MARK: - loweredRuntimeBuiltinCallee: Regex(String, Set) disambiguation

    @Test func testRegexConstructorWithUserDefinedSetDoesNotRouteToSetOverload() {
        let fixture = makeKIRDirectLoweringFixture()
        let interner = fixture.interner
        let types = fixture.types
        let symbols = fixture.symbols
        types.symbolTable = symbols

        let knownNames = KnownCompilerNames(interner: interner)

        // Define a user class "Set" with non-stdlib FQN
        let userSetClassSymbol = symbols.define(
            kind: .class,
            name: interner.intern("Set"),
            fqName: [interner.intern("com"), interner.intern("example"), interner.intern("Set")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let userSetType = types.make(.classType(ClassType(
            classSymbol: userSetClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        let stringType = types.stringType

        let regexCallee = interner.intern("Regex")
        let result = fixture.driver.callSupportLowerer.loweredRuntimeBuiltinCallee(
            for: regexCallee,
            argumentCount: 2,
            argumentTypes: [stringType, userSetType],
            interner: interner,
            types: types,
            knownNames: knownNames
        )

        // User-defined Set should NOT match set-like; should fall through
        // to the single-option overload kk_regex_create_with_option.
        #expect(
            result.map { interner.resolve($0) } == "__kk_regex_create_with_option_flat",
            "Regex(String, user-defined-Set) should NOT route to kk_regex_create_with_options"
        )
    }

    @Test func testRegexConstructorWithStdlibSetRoutesToSetOverload() {
        let fixture = makeKIRDirectLoweringFixture()
        let interner = fixture.interner
        let types = fixture.types
        let symbols = fixture.symbols
        types.symbolTable = symbols

        let knownNames = KnownCompilerNames(interner: interner)

        // Define stdlib Set with correct FQN
        let stdlibSetClassSymbol = symbols.define(
            kind: .class,
            name: interner.intern("Set"),
            fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Set")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let stdlibSetType = types.make(.classType(ClassType(
            classSymbol: stdlibSetClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        let stringType = types.stringType

        let regexCallee = interner.intern("Regex")
        let result = fixture.driver.callSupportLowerer.loweredRuntimeBuiltinCallee(
            for: regexCallee,
            argumentCount: 2,
            argumentTypes: [stringType, stdlibSetType],
            interner: interner,
            types: types,
            knownNames: knownNames
        )

        #expect(
            result.map { interner.resolve($0) } == "__kk_regex_create_with_options_flat",
            "Regex(String, stdlib-Set) should route to kk_regex_create_with_options"
        )
    }

    @Test func testAtomicArrayClassesAreRuntimeFactorySymbols() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)
        let names = [
            ["kotlin", "concurrent", "AtomicIntArray"],
            ["kotlin", "concurrent", "AtomicLongArray"],
            ["kotlin", "concurrent", "AtomicArray"],
            ["kotlin", "concurrent", "atomics", "AtomicIntArray"],
            ["kotlin", "concurrent", "atomics", "AtomicLongArray"],
            ["kotlin", "concurrent", "atomics", "AtomicArray"],
        ]
        for fqName in names {
            let interned = fqName.map(interner.intern)
            let symbol = symbols.define(
                kind: .class,
                name: interned.last!,
                fqName: interned,
                declSite: nil,
                visibility: .public,
                flags: []
            )
            let info = symbols.symbol(symbol)!
            #expect(
                knownNames.isAtomicScalarFactorySymbol(info),
                Comment(rawValue: fqName.joined(separator: ".") + " constructor must lower as a runtime factory")
            )
        }
    }
}
#endif
