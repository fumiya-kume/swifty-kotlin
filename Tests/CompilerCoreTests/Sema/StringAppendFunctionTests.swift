@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-003: Validates `append` on StringBuilder and Appendable.
@Suite
struct StringAppendFunctionTests {
    @Test func testAppendResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.text.Appendable

        fun main() {
            val sb = StringBuilder()
            val anyValue: Any? = 42
            val nullableString: String? = null
            sb.append(anyValue)
            sb.append(nullableString)
            sb.append('x')
            sb.append(true)
            sb.append(1)
            sb.append(2L)
            sb.append(3.5f)
            sb.append(4.5)
        }

        fun appendPieces(target: Appendable): Appendable {
            target.append('a')
            target.append("bc")
            return target.append("def", 1, 3)
        }
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected append overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let interner = ctx.interner
        let sema = try #require(ctx.sema)

        let stringBuilderSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
        ]))
        let appendableSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Appendable"),
        ]))
        let charSequenceSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("CharSequence"),
        ]))
        let anySymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("Any"),
        ]))
        #expect(sema.symbols.isSourceBackedSymbol(stringBuilderSymbol))
        #expect(
            Set(sema.symbols.directSupertypes(for: stringBuilderSymbol))
                == Set([appendableSymbol, charSequenceSymbol, anySymbol])
        )

        let stringBuilderAppendSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
            interner.intern("append"),
        ])

        let objectLikeTypes = [
            sema.types.nullableAnyType,
            sema.types.makeNullable(sema.types.stringType),
        ]
        for parameterType in objectLikeTypes {
            let overload = stringBuilderAppendSymbols.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes == [parameterType]
            }
            #expect(overload != nil, "Expected StringBuilder.append overload for \(parameterType)")
            if let overload {
                #expect(
                    sema.symbols.externalLinkName(for: overload) == nil,
                    "StringBuilder.append overload for \(parameterType) should be source-backed"
                )
            }
        }

        let typedParameterTypes = [
            sema.types.charType,
            sema.types.booleanType,
            sema.types.intType,
            sema.types.longType,
            sema.types.floatType,
            sema.types.doubleType,
        ]

        for parameterType in typedParameterTypes {
            let overload = stringBuilderAppendSymbols.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes == [parameterType]
            }
            #expect(overload != nil, "Expected StringBuilder.append overload for \(parameterType)")
            if let overload {
                #expect(
                    sema.symbols.externalLinkName(for: overload) == nil,
                    "StringBuilder.append overload for \(parameterType) should be source-backed"
                )
            }
        }

        let appendableAppendSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Appendable"),
            interner.intern("append"),
        ])

        #expect(
            appendableAppendSymbols.contains { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes == [sema.types.charType]
                    && sema.symbols.externalLinkName(for: symbolID) == "__kk_string_builder_append_char"
            },
            "Expected Appendable.append(Char) to link to __kk_string_builder_append_char"
        )
        #expect(
            appendableAppendSymbols.contains { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes.count == 1
                    && sema.symbols.externalLinkName(for: symbolID) == "__kk_string_builder_append_obj"
            },
            "Expected Appendable.append(CharSequence?) to link to __kk_string_builder_append_obj"
        )
        #expect(
            appendableAppendSymbols.contains { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes.count == 3
                    && sema.symbols.externalLinkName(for: symbolID) == "__kk_string_builder_append_range"
            },
            "Expected Appendable.append(CharSequence?, Int, Int) to link to __kk_string_builder_append_range"
        )
    }
}
