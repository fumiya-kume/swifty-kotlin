@testable import CompilerCore
import XCTest

final class PropertyDelegateSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testObservablePropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let propertiesFQName = ["kotlin", "properties"].map { interner.intern($0) }
        let observableFQName = propertiesFQName + [interner.intern("ObservableProperty")]
        let readWriteFQName = propertiesFQName + [interner.intern("ReadWriteProperty")]
        let readOnlyFQName = propertiesFQName + [interner.intern("ReadOnlyProperty")]
        let kPropertyFQName = ["kotlin", "reflect", "KProperty"].map { interner.intern($0) }

        let observableSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: observableFQName))
        let readWriteSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: readWriteFQName))
        let readOnlySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: readOnlyFQName))
        let kPropertySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kPropertyFQName))
        let observableInfo = try XCTUnwrap(sema.symbols.symbol(observableSymbol))
        XCTAssertEqual(observableInfo.kind, .class)
        XCTAssertTrue(observableInfo.flags.contains(.abstractType))
        XCTAssertEqual(sema.symbols.directSupertypes(for: observableSymbol), [readWriteSymbol])
        try assertNominalTypeParameters(
            for: readWriteSymbol,
            names: ["T", "V"],
            variances: [.in, .invariant],
            sema: sema,
            interner: interner
        )
        try assertNominalTypeParameters(
            for: readOnlySymbol,
            names: ["T", "V"],
            variances: [.in, .out],
            sema: sema,
            interner: interner
        )

        let typeParams = sema.types.nominalTypeParameterSymbols(for: observableSymbol)
        XCTAssertEqual(typeParams.count, 1)
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: observableSymbol, supertype: readWriteSymbol),
            [.in(sema.types.nullableAnyType), .invariant(valueType)]
        )

        let observableType = sema.types.make(.classType(ClassType(
            classSymbol: observableSymbol,
            args: [.invariant(valueType)],
            nullability: .nonNull
        )))
        let kPropertyType = sema.types.make(.classType(ClassType(
            classSymbol: kPropertySymbol,
            args: [.star],
            nullability: .nonNull
        )))

        let initSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: observableFQName + [interner.intern("<init>")]))
        let initSignature = try XCTUnwrap(sema.symbols.functionSignature(for: initSymbol))
        XCTAssertEqual(initSignature.parameterTypes, [valueType])
        XCTAssertEqual(initSignature.returnType, observableType)
        XCTAssertEqual(initSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(initSignature.classTypeParameterCount, 1)

        try assertMember(
            named: "beforeChange",
            visibility: .protected,
            requiredFlags: [.openType],
            parameterTypes: [kPropertyType, valueType, valueType],
            returnType: sema.types.booleanType,
            ownerFQName: observableFQName,
            ownerType: observableType,
            typeParams: typeParams,
            sema: sema,
            interner: interner
        )
        try assertMember(
            named: "afterChange",
            visibility: .protected,
            requiredFlags: [.openType],
            parameterTypes: [kPropertyType, valueType, valueType],
            returnType: sema.types.unitType,
            ownerFQName: observableFQName,
            ownerType: observableType,
            typeParams: typeParams,
            sema: sema,
            interner: interner
        )
        try assertMember(
            named: "getValue",
            requiredFlags: [.operatorFunction, .overrideMember, .openType],
            parameterTypes: [sema.types.nullableAnyType, kPropertyType],
            returnType: valueType,
            ownerFQName: observableFQName,
            ownerType: observableType,
            typeParams: typeParams,
            sema: sema,
            interner: interner
        )
        try assertMember(
            named: "setValue",
            requiredFlags: [.operatorFunction, .overrideMember, .openType],
            parameterTypes: [sema.types.nullableAnyType, kPropertyType, valueType],
            returnType: sema.types.unitType,
            ownerFQName: observableFQName,
            ownerType: observableType,
            typeParams: typeParams,
            sema: sema,
            interner: interner
        )
    }

    func testDelegatesObservableAndVetoableStayBackedByReadWriteProperty() throws {
        let (sema, interner) = try makeSema()
        let propertiesFQName = ["kotlin", "properties"].map { interner.intern($0) }
        let delegatesFQName = propertiesFQName + [interner.intern("Delegates")]
        let readWriteFQName = propertiesFQName + [interner.intern("ReadWriteProperty")]
        let delegatesSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: delegatesFQName))
        let readWriteSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: readWriteFQName))
        let delegatesType = sema.types.make(.classType(ClassType(
            classSymbol: delegatesSymbol,
            args: [],
            nullability: .nonNull
        )))
        let readWriteType = sema.types.make(.classType(ClassType(
            classSymbol: readWriteSymbol,
            args: [],
            nullability: .nonNull
        )))

        for memberName in ["observable", "vetoable"] {
            let memberSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: delegatesFQName + [interner.intern(memberName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
            XCTAssertEqual(signature.receiverType, delegatesType)
            XCTAssertEqual(signature.parameterTypes, [sema.types.anyType])
            XCTAssertEqual(signature.returnType, readWriteType)
        }
    }

    private func assertMember(
        named name: String,
        visibility: Visibility = .public,
        requiredFlags: SymbolFlags,
        parameterTypes: [TypeID],
        returnType: TypeID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        typeParams: [SymbolID],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ownerFQName + [interner.intern(name)]),
            file: file,
            line: line
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol), file: file, line: line)
        XCTAssertEqual(info.visibility, visibility, file: file, line: line)
        XCTAssertTrue(info.flags.isSuperset(of: requiredFlags), file: file, line: line)
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol), file: file, line: line)
        XCTAssertEqual(signature.receiverType, ownerType, file: file, line: line)
        XCTAssertEqual(signature.parameterTypes, parameterTypes, file: file, line: line)
        XCTAssertEqual(signature.returnType, returnType, file: file, line: line)
        XCTAssertEqual(signature.typeParameterSymbols, typeParams, file: file, line: line)
        XCTAssertEqual(signature.classTypeParameterCount, 1, file: file, line: line)
    }

    private func assertNominalTypeParameters(
        for symbol: SymbolID,
        names: [String],
        variances: [TypeVariance],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: symbol)
        XCTAssertEqual(typeParameters.count, names.count, file: file, line: line)
        let resolvedNames = try typeParameters.map { parameterSymbol in
            try interner.resolve(XCTUnwrap(sema.symbols.symbol(parameterSymbol)?.name, file: file, line: line))
        }
        XCTAssertEqual(resolvedNames, names, file: file, line: line)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: symbol), variances, file: file, line: line)
    }
}
