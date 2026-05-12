@testable import CompilerCore
import XCTest

final class JsDateExternalClassTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Date external class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testDateClassAndNestedTypesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let dateFQName = ["kotlin", "js", "Date"].map { interner.intern($0) }
        let dateSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: dateFQName),
            "kotlin.js.Date must be registered"
        )
        let dateInfo = try XCTUnwrap(sema.symbols.symbol(dateSymbol))

        XCTAssertEqual(dateInfo.kind, .class)
        XCTAssertEqual(dateInfo.visibility, .public)
        XCTAssertTrue(dateInfo.flags.contains(.synthetic))
        XCTAssertNotNil(sema.symbols.propertyType(for: dateSymbol))

        let companion = try XCTUnwrap(sema.symbols.companionObjectSymbol(for: dateSymbol))
        XCTAssertEqual(sema.symbols.symbol(companion)?.kind, .object)
        XCTAssertEqual(sema.symbols.symbol(companion)?.visibility, .public)

        let localeOptionsSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: dateFQName + [interner.intern("LocaleOptions")])
        )
        XCTAssertEqual(sema.symbols.symbol(localeOptionsSymbol)?.kind, .interface)

        let jsonSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "js", "Json"].map { interner.intern($0) })
        )
        XCTAssertEqual(sema.symbols.symbol(jsonSymbol)?.kind, .interface)
    }

    func testDateConstructorOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let ctorFQName = ["kotlin", "js", "Date", "<init>"].map { interner.intern($0) }
        let constructors = sema.symbols.lookupAll(fqName: ctorFQName)
        let signatures = constructors.compactMap { sema.symbols.functionSignature(for: $0) }
        let int = sema.types.intType
        let number = sema.types.anyType

        let expected: [[TypeID]] = [
            [],
            [number],
            [sema.types.stringType],
            [int, int],
            [int, int, int],
            [int, int, int, int],
            [int, int, int, int, int],
            [int, int, int, int, int, int],
            [int, int, int, int, int, int, number],
        ]

        for parameters in expected {
            let signature = try XCTUnwrap(
                signatures.first { $0.parameterTypes == parameters },
                "Date constructor parameters \(parameters) must be registered"
            )
            XCTAssertEqual(signature.returnType, try dateType(sema: sema, interner: interner))
            XCTAssertEqual(
                signature.valueParameterHasDefaultValues,
                Array(repeating: false, count: parameters.count)
            )
            XCTAssertEqual(signature.valueParameterIsVararg, Array(repeating: false, count: parameters.count))
        }
    }

    func testDateMemberFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let intMembers = [
            "getDate",
            "getDay",
            "getFullYear",
            "getHours",
            "getMilliseconds",
            "getMinutes",
            "getMonth",
            "getSeconds",
            "getTimezoneOffset",
            "getUTCDate",
            "getUTCDay",
            "getUTCFullYear",
            "getUTCHours",
            "getUTCMilliseconds",
            "getUTCMinutes",
            "getUTCMonth",
            "getUTCSeconds",
        ]
        for name in intMembers {
            try assertDateMember(
                named: name,
                parameters: [],
                returnType: sema.types.intType,
                defaultValues: [],
                sema: sema,
                interner: interner
            )
        }

        try assertDateMember(
            named: "getTime",
            parameters: [],
            returnType: sema.types.doubleType,
            defaultValues: [],
            sema: sema,
            interner: interner
        )

        for name in ["toDateString", "toISOString", "toTimeString", "toUTCString"] {
            try assertDateMember(
                named: name,
                parameters: [],
                returnType: sema.types.stringType,
                defaultValues: [],
                sema: sema,
                interner: interner
            )
        }

        try assertDateMember(
            named: "toJSON",
            parameters: [],
            returnType: try jsType(named: "Json", sema: sema, interner: interner),
            defaultValues: [],
            sema: sema,
            interner: interner
        )
    }

    func testLocaleMembersAndOptionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let dateFQName = ["kotlin", "js", "Date"].map { interner.intern($0) }
        let localeOptionsType = try dateNestedType(named: "LocaleOptions", sema: sema, interner: interner)
        let stringArray = try arrayType(element: sema.types.stringType, sema: sema, interner: interner)

        for name in ["toLocaleDateString", "toLocaleString", "toLocaleTimeString"] {
            try assertDateMember(
                named: name,
                parameters: [stringArray, localeOptionsType],
                returnType: sema.types.stringType,
                defaultValues: [true, true],
                sema: sema,
                interner: interner
            )
            try assertDateMember(
                named: name,
                parameters: [sema.types.stringType, localeOptionsType],
                returnType: sema.types.stringType,
                defaultValues: [false, true],
                sema: sema,
                interner: interner
            )
        }

        let localeOptionsFQName = dateFQName + [interner.intern("LocaleOptions")]
        let nullableString = sema.types.makeNullable(sema.types.stringType)
        for name in [
            "day",
            "era",
            "formatMatcher",
            "hour",
            "localeMatcher",
            "minute",
            "month",
            "second",
            "timeZone",
            "timeZoneName",
            "weekday",
            "year",
        ] {
            let property = try XCTUnwrap(sema.symbols.lookup(fqName: localeOptionsFQName + [interner.intern(name)]))
            XCTAssertEqual(sema.symbols.symbol(property)?.kind, .property)
            XCTAssertEqual(sema.symbols.propertyType(for: property), nullableString)
        }

        let hour12 = try XCTUnwrap(sema.symbols.lookup(fqName: localeOptionsFQName + [interner.intern("hour12")]))
        XCTAssertEqual(sema.symbols.symbol(hour12)?.kind, .property)
        XCTAssertEqual(sema.symbols.propertyType(for: hour12), sema.types.makeNullable(sema.types.booleanType))
    }

    private func assertDateMember(
        named name: String,
        parameters: [TypeID],
        returnType: TypeID,
        defaultValues: [Bool],
        sema: SemaModule,
        interner: StringInterner
    ) throws {
        let dateFQName = ["kotlin", "js", "Date"].map { interner.intern($0) }
        let memberFQName = dateFQName + [interner.intern(name)]
        let dateType = try dateType(sema: sema, interner: interner)
        let member = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: memberFQName).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == dateType
                    && signature.parameterTypes == parameters
                    && signature.returnType == returnType
            },
            "Date.\(name) with parameters \(parameters) must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: member))

        XCTAssertEqual(sema.symbols.symbol(member)?.visibility, .public)
        XCTAssertTrue(sema.symbols.symbol(member)?.flags.contains(.synthetic) == true)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, defaultValues)
        XCTAssertEqual(signature.valueParameterIsVararg, Array(repeating: false, count: parameters.count))
        XCTAssertNil(sema.symbols.externalLinkName(for: member))
    }

    private func dateType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        try jsType(named: "Date", sema: sema, interner: interner)
    }

    private func dateNestedType(
        named name: String,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        let fqName = ["kotlin", "js", "Date", name].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let type = try XCTUnwrap(sema.symbols.propertyType(for: symbol))
        return type
    }

    private func jsType(named name: String, sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let fqName = ["kotlin", "js", name].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let type = try XCTUnwrap(sema.symbols.propertyType(for: symbol))
        return type
    }

    private func arrayType(element: TypeID, sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let arrayFQName = ["kotlin", "Array"].map { interner.intern($0) }
        let arraySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: arrayFQName))
        return sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(element)],
            nullability: .nonNull
        )))
    }
}
