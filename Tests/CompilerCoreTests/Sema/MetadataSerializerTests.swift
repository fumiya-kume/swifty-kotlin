#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct MetadataSerializerTests {
    // MARK: - Helpers

    /// Parse the serialized record line (after the header) into space-separated tokens,
    /// then extract key=value pairs for precise field assertions.
    private func parseRecordLine(_ output: String) -> (kind: String, mangledName: String, fields: [String: String]) {
        // The serialized format is: "symbols=N\nkind mangledName key=val key=val...\n"
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 2 else { return ("", "", [:]) }
        let recordLine = String(lines[1])
        let tokens = recordLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 2 else { return ("", "", [:]) }
        let kind = tokens[0]
        let mangledName = tokens[1]
        var fields: [String: String] = [:]
        for token in tokens.dropFirst(2) {
            if let eqIdx = token.firstIndex(of: "=") {
                let key = String(token[token.startIndex ..< eqIdx])
                let value = String(token[token.index(after: eqIdx)...])
                fields[key] = value
            }
        }
        return (kind, mangledName, fields)
    }

    // MARK: - MetadataRecord init

    @Test func testMetadataRecordDefaults() {
        let record = MetadataRecord(kind: .function)
        #expect(record.kind == .function)
        #expect(record.mangledName == "")
        #expect(record.fqName == "")
        #expect(record.arity == 0)
        #expect(!(record.isSuspend))
        #expect(!(record.isInline))
        #expect(record.typeSignature == nil)
        #expect(record.externalLinkName == nil)
        #expect(record.declaredFieldCount == nil)
        #expect(record.declaredInstanceSizeWords == nil)
        #expect(record.declaredVtableSize == nil)
        #expect(record.declaredItableSize == nil)
        #expect(record.superFQName == nil)
        #expect(record.fieldOffsets == nil)
        #expect(record.vtableSlots == nil)
        #expect(record.itableSlots == nil)
        #expect(!(record.isDataClass))
        #expect(!(record.isSealedClass))
        #expect(!(record.isValueClass))
        #expect(record.valueClassUnderlyingTypeSig == nil)
        #expect(record.sealedSubclassFQNames.isEmpty)
        #expect(record.annotations.isEmpty)
        #expect(record.propertyReceiverTypeSignature == nil)
        #expect(record.propertyGetterExternalLinkName == nil)
        #expect(!record.isMutable)
    }

    @Test func testMetadataRecordWithAllFields() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_mod__Foo__C__abc",
            fqName: "com.example.Foo",
            arity: 2,
            isSuspend: true,
            isInline: true,
            typeSignature: "sig",
            externalLinkName: "link",
            declaredFieldCount: 3,
            declaredInstanceSizeWords: 4,
            declaredVtableSize: 5,
            declaredItableSize: 6,
            superFQName: "com.example.Base",
            fieldOffsets: "f1@0,f2@1",
            vtableSlots: "m1@0",
            itableSlots: "i1@0",
            isDataClass: true,
            isSealedClass: true,
            annotations: [MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated")],
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I",
            sealedSubclassFQNames: ["com.example.SubA", "com.example.SubB"],
            propertyReceiverTypeSignature: "Lkotlin/reflect/KClass<*>;",
            propertyGetterExternalLinkName: "kk_fn_get_abc",
            isMutable: true
        )
        #expect(record.kind == .class)
        #expect(record.mangledName == "_KK_mod__Foo__C__abc")
        #expect(record.fqName == "com.example.Foo")
        #expect(record.arity == 2)
        #expect(record.isSuspend)
        #expect(record.isInline)
        #expect(record.typeSignature == "sig")
        #expect(record.externalLinkName == "link")
        #expect(record.declaredFieldCount == 3)
        #expect(record.declaredInstanceSizeWords == 4)
        #expect(record.declaredVtableSize == 5)
        #expect(record.declaredItableSize == 6)
        #expect(record.superFQName == "com.example.Base")
        #expect(record.isDataClass)
        #expect(record.isSealedClass)
        #expect(record.isValueClass)
        #expect(record.valueClassUnderlyingTypeSig == "I")
        #expect(record.sealedSubclassFQNames == ["com.example.SubA", "com.example.SubB"])
        #expect(record.annotations.count == 1)
        #expect(record.propertyReceiverTypeSignature == "Lkotlin/reflect/KClass<*>;")
        #expect(record.propertyGetterExternalLinkName == "kk_fn_get_abc")
        #expect(record.isMutable)
    }

    // MARK: - MetadataAnnotationRecord

    @Test func testAnnotationRecordDefaults() {
        let ann = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated")
        #expect(ann.annotationFQName == "kotlin.Deprecated")
        #expect(ann.arguments.isEmpty)
        #expect(ann.useSiteTarget == nil)
    }

    @Test func testAnnotationRecordWithAllFields() {
        let ann = MetadataAnnotationRecord(
            annotationFQName: "kotlin.Deprecated",
            arguments: ["Use newMethod instead", "WARNING"],
            useSiteTarget: "get"
        )
        #expect(ann.annotationFQName == "kotlin.Deprecated")
        #expect(ann.arguments == ["Use newMethod instead", "WARNING"])
        #expect(ann.useSiteTarget == "get")
    }

    @Test func testAnnotationRecordEquatable() {
        let ann1 = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated")
        let ann2 = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated")
        let ann3 = MetadataAnnotationRecord(annotationFQName: "kotlin.JvmStatic")
        #expect(ann1 == ann2)
        #expect(ann1 != ann3)
    }

    @Test func testMetadataAnnotationPayloadRoundTripsThroughDecoder() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_demo__Box__C__",
            fqName: "demo.Box",
            declaredFieldCount: 1,
            annotations: [MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["legacy"])]
        )

        let metadataAnnotation = encoder.metadataAnnotationRecord(for: record)
        #expect(metadataAnnotation.annotationFQName == KnownCompilerAnnotation.metadata.qualifiedName)
        #expect(metadataAnnotation.arguments.count == 1)

        let decoded = MetadataDecoder().decode(metadataAnnotation.arguments[0])
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .class)
        #expect(decoded[0].fqName == "demo.Box")
        #expect(decoded[0].declaredFieldCount == 1)
        #expect(decoded[0].annotations.first?.annotationFQName == "kotlin.Deprecated")
    }

    // MARK: - MetadataEncoder serialize

    @Test func testSerializeFunctionRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__add__F__sig",
            fqName: "test.add",
            arity: 2,
            isSuspend: false,
            isInline: false,
            typeSignature: "F2<I,I,I>"
        )
        let output = encoder.serialize([record])
        #expect(output.hasPrefix("symbols=1\n"))
        let parsed = parseRecordLine(output)
        #expect(parsed.kind == "function")
        #expect(parsed.fields["fq"] == "test.add")
        #expect(parsed.fields["arity"] == "2")
        #expect(parsed.fields["suspend"] == "0")
        #expect(parsed.fields["inline"] == "0")
        #expect(parsed.fields["sig"] == "F2<I,I,I>")
    }

    @Test func testSerializeSuspendFunction() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__fetch__F__sig",
            fqName: "test.fetch",
            arity: 1,
            isSuspend: true,
            isInline: true,
            typeSignature: "SF1<I,U>"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        #expect(parsed.fields["suspend"] == "1")
        #expect(parsed.fields["inline"] == "1")
    }

    @Test func testSerializeClassWithLayout() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Foo__C__",
            fqName: "test.Foo",
            declaredFieldCount: 3,
            declaredInstanceSizeWords: 5,
            declaredVtableSize: 2,
            declaredItableSize: 1,
            superFQName: "test.Base",
            fieldOffsets: "test.Foo.x@0,test.Foo.y@1",
            vtableSlots: "test.Foo.bar#0#0@0",
            itableSlots: "test.IFoo.baz@0"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        #expect(parsed.kind == "class")
        #expect(parsed.fields["layoutWords"] == "5")
        #expect(parsed.fields["fields"] == "3")
        #expect(parsed.fields["vtable"] == "2")
        #expect(parsed.fields["itable"] == "1")
        #expect(parsed.fields["superFq"] == "test.Base")
        #expect(parsed.fields["fieldOffsets"] == "test.Foo.x@0,test.Foo.y@1")
        #expect(parsed.fields["vtableSlots"] == "test.Foo.bar#0#0@0")
        #expect(parsed.fields["itableSlots"] == "test.IFoo.baz@0")
    }

    @Test func testSerializeDataClassFlag() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Data__C__",
            fqName: "test.Data",
            isDataClass: true
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        #expect(parsed.fields["dataClass"] == "1")
    }

    @Test func testSerializeSealedClassFlag() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Sealed__C__",
            fqName: "test.Sealed",
            isSealedClass: true,
            sealedSubclassFQNames: ["test.SubA", "test.SubB"]
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        #expect(parsed.fields["sealedClass"] == "1")
        #expect(parsed.fields["sealedSubs"] == "test.SubA,test.SubB")
    }

    @Test func testSerializeValueClassFlag() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Wrapper__C__",
            fqName: "test.Wrapper",
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        #expect(parsed.fields["valueClass"] == "1")
        #expect(parsed.fields["valueUnderlying"] == "I")
    }

    @Test func testSerializePropertyWithSignature() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .property,
            mangledName: "_KK_test__x__P__I",
            fqName: "test.x",
            typeSignature: "I"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        #expect(parsed.kind == "property")
        #expect(parsed.fields["sig"] == "I")
    }

    @Test func testSerializeTypeAliasWithSignature() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .typeAlias,
            mangledName: "_KK_test__MyInt__T__I",
            fqName: "test.MyInt",
            typeSignature: "I"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        #expect(parsed.kind == "typeAlias")
        #expect(parsed.fields["sig"] == "I")
    }

    @Test func testSerializeConstructorRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .constructor,
            mangledName: "_KK_test__Foo__init__K__sig",
            fqName: "test.Foo.init",
            arity: 1,
            typeSignature: "F1<I,U>",
            externalLinkName: "Foo_init"
        )
        let output = encoder.serialize([record])
        let parsed = parseRecordLine(output)
        #expect(parsed.kind == "constructor")
        #expect(parsed.fields["arity"] == "1")
        #expect(parsed.fields["link"] == "Foo_init")
    }

    @Test func testSerializeAnnotations() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__fn__F__sig",
            fqName: "test.fn",
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["old"],
                    useSiteTarget: "get"
                ),
            ]
        )
        let output = encoder.serialize([record])
        #expect(output.contains("annotations="))
        #expect(output.contains("kotlin.Deprecated"))
        #expect(output.contains("target:get"))
    }

    @Test func testBuildRecordSkipsMissingValueClassUnderlyingType() throws {
        let encoder = MetadataEncoder()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let symbol = symbols.define(
            kind: .class,
            name: interner.intern("Wrapper"),
            fqName: [interner.intern("demo"), interner.intern("Wrapper")],
            declSite: nil,
            visibility: .public,
            flags: [.valueType]
        )

        let record = encoder.buildRecord(
            for: try #require(symbols.symbol(symbol)),
            symbols: symbols,
            types: types,
            moduleName: "Demo",
            interner: interner
        )

        #expect(record.isValueClass)
        #expect(record.valueClassUnderlyingTypeSig == nil)
    }

    @Test func testBuildRecordsCanExportSyntheticNominalAnchorsOnly() throws {
        let encoder = MetadataEncoder()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let kotlin = interner.intern("kotlin")

        let charSequence = symbols.define(
            kind: .interface,
            name: interner.intern("CharSequence"),
            fqName: [kotlin, interner.intern("CharSequence")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let range = symbols.define(
            kind: .class,
            name: interner.intern("IntRange"),
            fqName: [kotlin, interner.intern("ranges"), interner.intern("IntRange")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let first = symbols.define(
            kind: .property,
            name: interner.intern("first"),
            fqName: [kotlin, interner.intern("ranges"), interner.intern("IntRange"), interner.intern("first")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: 1,
                instanceSizeWords: 3,
                fieldOffsets: [first: 2],
                vtableSlots: [first: 0],
                itableSlots: [charSequence: 0],
                superClass: nil
            ),
            for: range
        )
        let function = symbols.define(
            kind: .function,
            name: interner.intern("syntheticFunction"),
            fqName: [kotlin, interner.intern("syntheticFunction")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [],
                returnType: types.unitType,
                isSuspend: false
            ),
            for: function
        )

        let records = encoder.buildRecords(
            symbols: symbols,
            types: types,
            moduleName: "Stdlib",
            interner: interner,
            functionLinkNames: [:],
            includeSynthetic: false,
            includeSyntheticNominalAnchors: true
        )

        #expect(records.map(\.fqName) == ["kotlin.CharSequence", "kotlin.ranges.IntRange"])
        #expect(records.map(\.kind) == [.interface, .class])
        #expect(records.allSatisfy { !$0.mangledName.isEmpty })
        let charSequenceRecord = try #require(records.first { $0.fqName == "kotlin.CharSequence" })
        #expect(charSequenceRecord.declaredInstanceSizeWords == nil)
        let intRange = try #require(records.first { $0.fqName == "kotlin.ranges.IntRange" })
        #expect(intRange.declaredFieldCount == 1)
        #expect(intRange.declaredInstanceSizeWords == 3)
        #expect(intRange.declaredVtableSize == 1)
        #expect(intRange.declaredItableSize == 1)
        #expect(records.allSatisfy { $0.fieldOffsets == nil })
        #expect(records.allSatisfy { $0.vtableSlots == nil })
        #expect(records.allSatisfy { $0.itableSlots == nil })
    }

    @Test func testSerializeVTableSlotsUsesOwningPropertyForSyntheticGetter() throws {
        let encoder = MetadataEncoder()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let demo = interner.intern("demo")
        let boxName = interner.intern("Box")
        let valueName = interner.intern("value")

        let box = symbols.define(
            kind: .class,
            name: boxName,
            fqName: [demo, boxName],
            declSite: nil,
            visibility: .public
        )
        let value = symbols.define(
            kind: .property,
            name: valueName,
            fqName: [demo, boxName, valueName],
            declSite: nil,
            visibility: .protected,
            flags: [.abstractType]
        )
        symbols.setParentSymbol(box, for: value)
        symbols.setPropertyType(types.intType, for: value)

        let getter = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: value)
        let serialized = encoder.serializeVTableSlots(
            [getter: 3],
            symbols: symbols,
            interner: interner,
            includedSymbolIDs: Set<SymbolID>(),
            mangler: NameMangler(),
            types: types
        )

        #expect(serialized == "v2:pget:demo.Box.value@3")
    }

    @Test func testSerializeMultipleRecords() {
        let encoder = MetadataEncoder()
        let records = [
            MetadataRecord(kind: .function, mangledName: "m1", fqName: "test.fn1"),
            MetadataRecord(kind: .class, mangledName: "m2", fqName: "test.Cls"),
        ]
        let output = encoder.serialize(records)
        #expect(output.hasPrefix("symbols=2\n"))
        #expect(output.contains("function"))
        #expect(output.contains("class"))
    }

    @Test func testSerializeEmptyRecords() {
        let encoder = MetadataEncoder()
        let output = encoder.serialize([])
        #expect(output == "symbols=0\n")
    }

    // MARK: - MetadataDecoder

    @Test func testDecodeFunctionRecord() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nfunction _KK_test__fn__F__sig fq=test.fn schema=v1 arity=2 suspend=0 inline=0 sig=F2<I,I,I>\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].kind == .function)
        #expect(records[0].fqName == "test.fn")
        #expect(records[0].arity == 2)
        #expect(!(records[0].isSuspend))
        #expect(!(records[0].isInline))
        #expect(records[0].typeSignature == "F2<I,I,I>")
    }

    @Test func testDecodeSuspendFunction() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nfunction _KK fq=test.fn schema=v1 arity=1 suspend=1 inline=1 sig=SF1<I,U>\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].isSuspend)
        #expect(records[0].isInline)
    }

    @Test func testDecodeClassWithLayout() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Foo schema=v1 layoutWords=5 fields=3 vtable=2 itable=1 superFq=test.Base fieldOffsets=x@0 vtableSlots=bar@0 itableSlots=baz@0\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].kind == .class)
        #expect(records[0].declaredInstanceSizeWords == 5)
        #expect(records[0].declaredFieldCount == 3)
        #expect(records[0].declaredVtableSize == 2)
        #expect(records[0].declaredItableSize == 1)
        #expect(records[0].superFQName == "test.Base")
        #expect(records[0].fieldOffsets == "x@0")
        #expect(records[0].vtableSlots == "bar@0")
        #expect(records[0].itableSlots == "baz@0")
    }

    @Test func testBuildRecordsPreservesNominalSupertypeSignaturesForNonGenericClass() {
        let encoder = MetadataEncoder()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let kotlin = interner.intern("kotlin")
        let myPack = interner.intern("test")

        let enumBase = symbols.define(
            kind: .class,
            name: interner.intern("Enum"),
            fqName: [kotlin, interner.intern("Enum")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let typeParamE = symbols.define(
            kind: .typeParameter,
            name: interner.intern("E"),
            fqName: [kotlin, interner.intern("Enum"), interner.intern("E")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamE], for: enumBase)

        let myEnum = symbols.define(
            kind: .enumClass,
            name: interner.intern("MyEnum"),
            fqName: [myPack, interner.intern("MyEnum")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        symbols.setDirectSupertypes([enumBase], for: myEnum)
        let myEnumType = types.make(.classType(ClassType(classSymbol: myEnum, args: [], nullability: .nonNull)))
        let superArgs: [TypeArg] = [.invariant(myEnumType)]
        types.setNominalSupertypeTypeArgs(superArgs, for: myEnum, supertype: enumBase)

        let records = encoder.buildRecords(
            symbols: symbols,
            types: types,
            moduleName: "TestModule",
            interner: interner,
            functionLinkNames: [:],
            includeSynthetic: false,
            includeSyntheticNominalAnchors: false
        )

        let myEnumRecord = records.first { $0.fqName == "test.MyEnum" }
        #expect(myEnumRecord != nil)
        #expect(myEnumRecord?.nominalSupertypeSignatures.isEmpty == false)
    }
}
#endif
