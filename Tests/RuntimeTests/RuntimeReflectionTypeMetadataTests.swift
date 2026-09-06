@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeReflectionTypeMetadataTests {
    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    private func nominalToken(_ typeID: Int64) -> Int {
        Int(truncatingIfNeeded: (typeID << 9) | 6)
    }

    @Test func reflectionBoxesCarryNominalHierarchyAndSharedNameDispatch() {
        registerReflectionRuntimeTypeMetadata()

        let functionName = makeRuntimeString("run")
        let propertyName = makeRuntimeString("value")
        let constructorName = makeRuntimeString("<init>")
        let function = __kk_kfunction_create(
            functionName, 0, makeRuntimeString("kotlin.String"), 0, 0, 0
        )
        let property = kk_kproperty_stub_create(propertyName, makeRuntimeString("kotlin.Int"))
        let kclass = __kk_kclass_create(71001, makeRuntimeString("Sample"))
        let constructor = __kk_kconstructor_create(
            constructorName, 0, makeRuntimeString("Sample"), 0, 1, 0, kclass
        )

        #expect(runtimeObjectTypeID(rawValue: function) == kFunctionRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: property) == kPropertyRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: constructor) == kConstructorRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: kclass) == kClassRuntimeTypeID)

        #expect(kk_op_is(function, nominalToken(kCallableRuntimeTypeID)) == 1)
        #expect(kk_op_is(function, nominalToken(kFunctionRuntimeTypeID)) == 1)
        #expect(kk_op_is(property, nominalToken(kCallableRuntimeTypeID)) == 1)
        #expect(kk_op_is(property, nominalToken(kPropertyRuntimeTypeID)) == 1)
        #expect(kk_op_is(constructor, nominalToken(kCallableRuntimeTypeID)) == 1)
        #expect(kk_op_is(constructor, nominalToken(kFunctionRuntimeTypeID)) == 1)
        #expect(kk_op_is(constructor, nominalToken(kConstructorRuntimeTypeID)) == 1)
        #expect(kk_op_is(kclass, nominalToken(kClassifierRuntimeTypeID)) == 1)

        #expect(__kk_kcallable_get_name(function) == functionName)
        #expect(__kk_kcallable_get_name(property) == propertyName)
        #expect(__kk_kcallable_get_name(constructor) == constructorName)

        let functionReturnType = __kk_kcallable_get_return_type(function)
        let propertyReturnType = __kk_kcallable_get_return_type(property)
        let constructorReturnType = __kk_kcallable_get_return_type(constructor)
        #expect(runtimeObjectTypeID(rawValue: functionReturnType) == kTypeRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: propertyReturnType) == kTypeRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: constructorReturnType) == kTypeRuntimeTypeID)
        #expect(__kk_ktype_classifier(functionReturnType) != runtimeNullSentinelInt)
        #expect(runtimeRenderAnyForPrint(functionReturnType) == "kotlin.String")
        #expect(runtimeRenderAnyForPrint(propertyReturnType) == "kotlin.Int")
        #expect(runtimeRenderAnyForPrint(constructorReturnType) == "Sample")

        let taggedFunction = kk_callable_ref_tag_kfunction(
            function, functionName, makeRuntimeString("kotlin.String"), 0, 0
        )
        let taggedProperty = kk_callable_ref_tag_kproperty(
            property, propertyName, makeRuntimeString("kotlin.Int"), 0
        )
        #expect(runtimeObjectTypeID(rawValue: __kk_kcallable_get_return_type(taggedFunction)) == kTypeRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: __kk_kcallable_get_return_type(taggedProperty)) == kTypeRuntimeTypeID)
    }

    @Test func typeReflectionBoxesCarryTheirDeclaredNominalTypes() {
        registerReflectionRuntimeTypeMetadata()

        let ktype = kk_typeof(71002, makeRuntimeString("Sample"), 0, 0)
        let projection = __kk_ktypeprojection_create(ktype, 2)
        let parameter = __kk_kparameter_create(
            0, makeRuntimeString("value"), makeRuntimeString("kotlin.Int"), 0, 2
        )

        #expect(runtimeObjectTypeID(rawValue: ktype) == kTypeRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: projection) == kTypeProjectionRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: parameter) == kParameterRuntimeTypeID)
        #expect(kk_op_is(ktype, nominalToken(kClassifierRuntimeTypeID)) == 1)
        #expect(kk_op_is(ktype, nominalToken(kTypeRuntimeTypeID)) == 1)
    }
}
