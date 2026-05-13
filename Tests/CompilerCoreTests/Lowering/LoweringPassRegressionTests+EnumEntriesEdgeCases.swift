@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-023: kotlin.enums `entries` / `EnumEntries<T>` edge case coverage.
extension LoweringPassRegressionTests {

    // MARK: - Helpers

    private func makeEnumModule(
        enumName: String,
        entryNames: [String],
        interner: StringInterner,
        symbols: SymbolTable,
        types: TypeSystem,
        sema: SemaModule,
        moduleName: String
    ) throws -> (module: KIRModule, enumSymbol: SymbolID, ctx: CompilationContext) {
        let packagePath: [InternedString] = [interner.intern("test")]
        let enumInternedName = interner.intern(enumName)
        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: enumInternedName,
            fqName: packagePath + [enumInternedName],
            declSite: nil,
            visibility: .public
        )
        for entryName in entryNames {
            _ = symbols.define(
                kind: .field,
                name: interner.intern(entryName),
                fqName: packagePath + [enumInternedName, interner.intern(entryName)],
                declSite: nil,
                visibility: .public
            )
        }

        let arena = KIRArena()
        let decl = arena.appendDecl(.nominalType(KIRNominalType(symbol: enumSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [decl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)
        return (module, enumSymbol, ctx)
    }

    // MARK: - STDLIB-023-01: entries$get is synthesized for a normal enum

    func testEnumEntriesGetterIsSynthesized() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Color",
            entryNames: ["RED", "GREEN", "BLUE"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumEntriesGetter"
        )

        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(fn) = decl else { return nil }
            return interner.resolve(fn.name)
        }

        XCTAssertTrue(functionNames.contains("entries$get"),
                      "entries$get should be synthesized; got: \(functionNames)")
    }

    // MARK: - STDLIB-023-02: entries$get body calls kk_array_new and kk_enum_make_entries_list

    func testEnumEntriesGetterBodyUsesCorrectRuntimeCalls() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Direction",
            entryNames: ["NORTH", "SOUTH", "EAST", "WEST"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumEntriesRuntimeCalls"
        )

        let fn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let callees = extractCallees(from: fn.body, interner: interner)

        XCTAssertTrue(callees.contains("kk_array_new"),
                      "entries$get should call kk_array_new; callees: \(callees)")
        XCTAssertTrue(callees.contains("kk_array_set"),
                      "entries$get should call kk_array_set for each entry; callees: \(callees)")
        XCTAssertTrue(callees.contains("kk_enum_make_entries_list"),
                      "entries$get should call kk_enum_make_entries_list; callees: \(callees)")
    }

    // MARK: - STDLIB-023-03: entries count matches declared enum cases

    func testEnumEntriesCountMatchesDeclaredCases() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Planet",
            entryNames: ["MERCURY", "VENUS", "EARTH", "MARS", "JUPITER"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumEntriesCount"
        )

        // The count helper Planet$enumValuesCount must return 5.
        let countFn = try findKIRFunction(named: "Planet$enumValuesCount", in: module, interner: interner)
        let intConsts = countFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        XCTAssertTrue(intConsts.contains(5),
                      "Planet$enumValuesCount should embed count=5; got consts: \(intConsts)")

        // entries$get must embed 5 ordinal literals (one per entry set).
        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let entriesConsts = entriesFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        // 5-entry enum: ordinals 0..4 appear as both index and entry payload.
        XCTAssertTrue(entriesConsts.contains(4),
                      "entries$get should embed ordinal 4 (5th entry); got: \(entriesConsts)")
    }

    // MARK: - STDLIB-023-04: entries order matches declaration order

    func testEnumEntriesOrderMatchesDeclaration() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Season",
            entryNames: ["SPRING", "SUMMER", "AUTUMN", "WINTER"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumEntriesOrder"
        )

        // Per-entry ordinal functions must return 0, 1, 2, 3 in declaration order.
        for (expectedOrdinal, name) in ["SPRING", "SUMMER", "AUTUMN", "WINTER"].enumerated() {
            let fn = try findKIRFunction(named: "\(name)$enumOrdinal", in: module, interner: interner)
            let consts = fn.body.compactMap { inst -> Int64? in
                guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
                return v
            }
            XCTAssertTrue(consts.contains(Int64(expectedOrdinal)),
                          "\(name)$enumOrdinal should be \(expectedOrdinal); got: \(consts)")
        }
    }

    // MARK: - STDLIB-023-05: empty enum synthesizes zero-count helpers

    func testEmptyEnumSynthesizesZeroCount() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Empty",
            entryNames: [],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumEntriesEmpty"
        )

        let countFn = try findKIRFunction(named: "Empty$enumValuesCount", in: module, interner: interner)
        let intConsts = countFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        XCTAssertTrue(intConsts.contains(0),
                      "Empty enum should have count=0; got: \(intConsts)")

        // entries$get must NOT call kk_array_set (no entries to populate).
        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let callees = extractCallees(from: entriesFn.body, interner: interner)
        XCTAssertFalse(callees.contains("kk_array_set"),
                       "Empty enum entries$get must not call kk_array_set; callees: \(callees)")
        XCTAssertTrue(callees.contains("kk_enum_make_entries_list"),
                      "Empty enum entries$get must still call kk_enum_make_entries_list; callees: \(callees)")
    }

    // MARK: - STDLIB-023-06: single-variant enum

    func testSingleVariantEnumEntriesAndOrdinal() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Singleton",
            entryNames: ["ONLY"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumEntriesSingle"
        )

        let countFn = try findKIRFunction(named: "Singleton$enumValuesCount", in: module, interner: interner)
        let countConsts = countFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        XCTAssertTrue(countConsts.contains(1), "Single-variant enum count should be 1; got: \(countConsts)")

        let ordinalFn = try findKIRFunction(named: "ONLY$enumOrdinal", in: module, interner: interner)
        let ordinalConsts = ordinalFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        XCTAssertTrue(ordinalConsts.contains(0), "ONLY ordinal should be 0; got: \(ordinalConsts)")

        let nameFn = try findKIRFunction(named: "ONLY$enumName", in: module, interner: interner)
        let nameConsts = nameFn.body.compactMap { inst -> InternedString? in
            guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
            return s
        }
        XCTAssertTrue(nameConsts.contains(interner.intern("ONLY")),
                      "ONLY$enumName should return \"ONLY\"")
    }

    // MARK: - STDLIB-023-07: values() synthesized separately from entries$get

    func testEnumValuesAndEntriesGetterBothSynthesized() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Side",
            entryNames: ["LEFT", "RIGHT"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumValuesAndEntries"
        )

        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(fn) = decl else { return nil }
            return interner.resolve(fn.name)
        }
        XCTAssertTrue(functionNames.contains("values"),
                      "values() must be synthesized; got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("entries$get"),
                      "entries$get must be synthesized; got: \(functionNames)")

        // values() uses kk_enum_make_values_array; entries$get uses kk_enum_make_entries_list.
        let valuesFn = try findKIRFunction(named: "values", in: module, interner: interner)
        let valuesCallees = extractCallees(from: valuesFn.body, interner: interner)
        XCTAssertTrue(valuesCallees.contains("kk_enum_make_values_array"),
                      "values() should call kk_enum_make_values_array; callees: \(valuesCallees)")
        XCTAssertFalse(valuesCallees.contains("kk_enum_make_entries_list"),
                       "values() must NOT call kk_enum_make_entries_list; callees: \(valuesCallees)")

        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        let entriesCallees = extractCallees(from: entriesFn.body, interner: interner)
        XCTAssertTrue(entriesCallees.contains("kk_enum_make_entries_list"),
                      "entries$get should call kk_enum_make_entries_list; callees: \(entriesCallees)")
        XCTAssertFalse(entriesCallees.contains("kk_enum_make_values_array"),
                       "entries$get must NOT call kk_enum_make_values_array; callees: \(entriesCallees)")
    }

    // MARK: - STDLIB-023-08: valueOf is synthesized and calls kk_string_equals + kk_enum_valueOf_throw

    func testEnumValueOfSynthesizedWithStringComparisonAndThrow() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Status",
            entryNames: ["ACTIVE", "INACTIVE", "PENDING"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumValueOf"
        )

        let valueOfFn = try findKIRFunction(named: "valueOf", in: module, interner: interner)
        let callees = extractCallees(from: valueOfFn.body, interner: interner)

        XCTAssertTrue(callees.contains("kk_string_equals"),
                      "valueOf should call kk_string_equals; callees: \(callees)")
        XCTAssertTrue(callees.contains("kk_enum_valueOf_throw"),
                      "valueOf should call kk_enum_valueOf_throw; callees: \(callees)")
    }

    // MARK: - STDLIB-023-09: values() uses kk_enum_make_values_array (fresh array each call)

    func testEnumValuesFunctionCallsValueArrayRuntime() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Coin",
            entryNames: ["HEADS", "TAILS"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumValuesFreshArray"
        )

        let valuesFn = try findKIRFunction(named: "values", in: module, interner: interner)
        let callees = extractCallees(from: valuesFn.body, interner: interner)

        // values() should always produce a fresh array via kk_enum_make_values_array.
        XCTAssertTrue(callees.contains("kk_array_new"),
                      "values() should allocate a new array via kk_array_new; callees: \(callees)")
        XCTAssertTrue(callees.contains("kk_enum_make_values_array"),
                      "values() should wrap the array via kk_enum_make_values_array; callees: \(callees)")
    }

    // MARK: - STDLIB-023-10: all per-entry name/ordinal helpers are present

    func testAllPerEntryHelpersPresent() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let entryNames = ["ALPHA", "BETA", "GAMMA"]
        let (module, _, _) = try makeEnumModule(
            enumName: "Greek",
            entryNames: entryNames,
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumPerEntryHelpers"
        )

        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(fn) = decl else { return nil }
            return interner.resolve(fn.name)
        }

        for name in entryNames {
            XCTAssertTrue(functionNames.contains("\(name)$enumOrdinal"),
                          "Missing \(name)$enumOrdinal; got: \(functionNames)")
            XCTAssertTrue(functionNames.contains("\(name)$enumName"),
                          "Missing \(name)$enumName; got: \(functionNames)")
        }

        // Verify per-entry name strings are correct.
        for name in entryNames {
            let nameFn = try findKIRFunction(named: "\(name)$enumName", in: module, interner: interner)
            let nameConsts = nameFn.body.compactMap { inst -> InternedString? in
                guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
                return s
            }
            XCTAssertTrue(nameConsts.contains(interner.intern(name)),
                          "\(name)$enumName should return \"\(name)\"")
        }
    }

    // MARK: - STDLIB-023-11: valueOf body embeds enum class name prefix for error messages

    func testValueOfEmbedClassNamePrefixForError() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Fruit",
            entryNames: ["APPLE", "BANANA"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumValueOfErrorPrefix"
        )

        let valueOfFn = try findKIRFunction(named: "valueOf", in: module, interner: interner)
        let stringLiterals = valueOfFn.body.compactMap { inst -> String? in
            guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
            return interner.resolve(s)
        }
        // Kotlin error message format: "No enum constant Fruit.UNKNOWN"
        XCTAssertTrue(stringLiterals.contains("Fruit."),
                      "valueOf should embed \"Fruit.\" prefix for error messages; got: \(stringLiterals)")
    }

    // MARK: - STDLIB-023-12: entries$get takes no parameters (zero-param getter)

    func testEntriesGetterHasZeroParameters() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())

        let (module, _, _) = try makeEnumModule(
            enumName: "Flag",
            entryNames: ["ON", "OFF"],
            interner: interner,
            symbols: symbols,
            types: types,
            sema: sema,
            moduleName: "EnumEntriesZeroParams"
        )

        let entriesFn = try findKIRFunction(named: "entries$get", in: module, interner: interner)
        // entries is a property getter (no value parameters).
        XCTAssertEqual(entriesFn.params.count, 0,
                       "entries$get should have 0 parameters (property getter)")
    }

    func testTopLevelEnumEntriesCallUsesEntriesRuntime() throws {
        let source = """
        enum class Color { RED, GREEN }

        fun useEntries() = enumEntries<Color>()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "enumEntries<Color>() should compile without diagnostics")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "useEntries", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_enum_make_entries_list"),
                          "enumEntries<Color>() should call kk_enum_make_entries_list; callees: \(callees)")
            XCTAssertFalse(callees.contains("kk_enum_make_values_array"),
                           "enumEntries<Color>() must not call kk_enum_make_values_array; callees: \(callees)")
        }
    }
}
