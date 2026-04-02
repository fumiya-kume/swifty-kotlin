import Foundation

// Coercion extension stubs (STDLIB-150) for kotlin.ranges.
// Int/Long/Double/Float coercion tests: CoercionSyntheticStubTests (TEST-002)

extension DataFlowSemaPhase {
    func registerSyntheticCoercionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let kotlinRangesPkg = kotlinPkg + [interner.intern("ranges")]

        // Ensure packages exist
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(kind: .package, name: interner.intern("kotlin"), fqName: kotlinPkg, declSite: nil, visibility: .public, flags: [.synthetic])
        }
        let rangesPackageSymbol: SymbolID
        if let existing = symbols.lookup(fqName: kotlinRangesPkg) {
            rangesPackageSymbol = existing
        } else {
            rangesPackageSymbol = symbols.define(kind: .package, name: interner.intern("ranges"), fqName: kotlinRangesPkg, declSite: nil, visibility: .public, flags: [.synthetic])
            if let kotlinSym = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(kotlinSym, for: rangesPackageSymbol)
            }
        }

        // coerceIn(minimumValue: Int, maximumValue: Int): Int
        registerSyntheticCoercionFunction(
            named: "coerceIn",
            externalLinkName: "kk_int_coerceIn",
            receiverType: types.intType,
            parameters: [
                (name: "minimumValue", type: types.intType),
                (name: "maximumValue", type: types.intType),
            ],
            returnType: types.intType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoercionFunction(
            named: "coerceIn",
            externalLinkName: "kk_int_coerceIn",
            receiverType: types.intType,
            parameters: [(name: "range", type: types.intType)],
            returnType: types.intType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )

        // coerceAtLeast(minimumValue: Int): Int
        registerSyntheticCoercionFunction(
            named: "coerceAtLeast",
            externalLinkName: "kk_int_coerceAtLeast",
            receiverType: types.intType,
            parameters: [(name: "minimumValue", type: types.intType)],
            returnType: types.intType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )

        // coerceAtMost(maximumValue: Int): Int
        registerSyntheticCoercionFunction(
            named: "coerceAtMost",
            externalLinkName: "kk_int_coerceAtMost",
            receiverType: types.intType,
            parameters: [(name: "maximumValue", type: types.intType)],
            returnType: types.intType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- Long coercion (STDLIB-500) ---
        registerSyntheticCoercionFunction(
            named: "coerceIn",
            externalLinkName: "kk_long_coerceIn",
            receiverType: types.longType,
            parameters: [
                (name: "minimumValue", type: types.longType),
                (name: "maximumValue", type: types.longType),
            ],
            returnType: types.longType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoercionFunction(
            named: "coerceIn",
            externalLinkName: "kk_long_coerceIn",
            receiverType: types.longType,
            parameters: [(name: "range", type: types.longType)],
            returnType: types.longType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoercionFunction(
            named: "coerceAtLeast",
            externalLinkName: "kk_long_coerceAtLeast",
            receiverType: types.longType,
            parameters: [(name: "minimumValue", type: types.longType)],
            returnType: types.longType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoercionFunction(
            named: "coerceAtMost",
            externalLinkName: "kk_long_coerceAtMost",
            receiverType: types.longType,
            parameters: [(name: "maximumValue", type: types.longType)],
            returnType: types.longType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- Double coercion (STDLIB-500) ---
        registerSyntheticCoercionFunction(
            named: "coerceIn",
            externalLinkName: "kk_double_coerceIn",
            receiverType: types.doubleType,
            parameters: [
                (name: "minimumValue", type: types.doubleType),
                (name: "maximumValue", type: types.doubleType),
            ],
            returnType: types.doubleType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoercionFunction(
            named: "coerceAtLeast",
            externalLinkName: "kk_double_coerceAtLeast",
            receiverType: types.doubleType,
            parameters: [(name: "minimumValue", type: types.doubleType)],
            returnType: types.doubleType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoercionFunction(
            named: "coerceAtMost",
            externalLinkName: "kk_double_coerceAtMost",
            receiverType: types.doubleType,
            parameters: [(name: "maximumValue", type: types.doubleType)],
            returnType: types.doubleType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- Float coercion (STDLIB-500) ---
        registerSyntheticCoercionFunction(
            named: "coerceIn",
            externalLinkName: "kk_float_coerceIn",
            receiverType: types.floatType,
            parameters: [
                (name: "minimumValue", type: types.floatType),
                (name: "maximumValue", type: types.floatType),
            ],
            returnType: types.floatType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoercionFunction(
            named: "coerceAtLeast",
            externalLinkName: "kk_float_coerceAtLeast",
            receiverType: types.floatType,
            parameters: [(name: "minimumValue", type: types.floatType)],
            returnType: types.floatType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoercionFunction(
            named: "coerceAtMost",
            externalLinkName: "kk_float_coerceAtMost",
            receiverType: types.floatType,
            parameters: [(name: "maximumValue", type: types.floatType)],
            returnType: types.floatType,
            packageFQName: kotlinRangesPkg,
            packageSymbol: rangesPackageSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-510..511: roundToInt / roundToLong extension functions ---
        let kotlinMathPkg = kotlinPkg + [interner.intern("math")]
        if symbols.lookup(fqName: kotlinMathPkg) == nil {
            let mathName = interner.intern("math")
            let mathSym = symbols.define(kind: .package, name: mathName, fqName: kotlinMathPkg, declSite: nil, visibility: .public, flags: [.synthetic])
            if let kotlinSym = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(kotlinSym, for: mathSym)
            }
        }
        if let mathPackageSymbol = symbols.lookup(fqName: kotlinMathPkg) {
            registerSyntheticCoercionFunction(
                named: "pow",
                externalLinkName: "kk_math_pow",
                receiverType: types.doubleType,
                parameters: [(name: "x", type: types.doubleType)],
                returnType: types.doubleType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "roundToInt",
                externalLinkName: "kk_float_roundToInt",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "roundToInt",
                externalLinkName: "kk_double_roundToInt",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "roundToLong",
                externalLinkName: "kk_float_roundToLong",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "roundToLong",
                externalLinkName: "kk_double_roundToLong",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // --- STDLIB-512..513: ulp / nextUp / nextDown extension properties ---
            // Registered as zero-parameter extension functions (the property accessor pattern).
            registerSyntheticCoercionFunction(
                named: "ulp",
                externalLinkName: "kk_double_ulp",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.doubleType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "nextUp",
                externalLinkName: "kk_double_nextUp",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.doubleType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "nextDown",
                externalLinkName: "kk_double_nextDown",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.doubleType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "ulp",
                externalLinkName: "kk_float_ulp",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "nextUp",
                externalLinkName: "kk_float_nextUp",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "nextDown",
                externalLinkName: "kk_float_nextDown",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-NUM-130: isNaN / isInfinite / isFinite / toBits / fromBits

        // Int.countOneBits() / countLeadingZeroBits() / countTrailingZeroBits() (STDLIB-501)
        // STDLIB-BIT-007: Additional bit manipulation functions
        // Use if-let instead of guard-return so future registrations below are not skipped.
        if let kotlinPackageSymbol = symbols.lookup(fqName: kotlinPkg) {
            let boolType = types.make(.primitive(.boolean, .nonNull))

            // Double.isNaN() / isInfinite() / isFinite()
            registerSyntheticCoercionFunction(
                named: "isNaN",
                externalLinkName: "kk_double_isNaN",
                receiverType: types.doubleType,
                parameters: [],
                returnType: boolType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "isInfinite",
                externalLinkName: "kk_double_isInfinite",
                receiverType: types.doubleType,
                parameters: [],
                returnType: boolType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "isFinite",
                externalLinkName: "kk_double_isFinite",
                receiverType: types.doubleType,
                parameters: [],
                returnType: boolType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Float.isNaN() / isInfinite() / isFinite()
            registerSyntheticCoercionFunction(
                named: "isNaN",
                externalLinkName: "kk_float_isNaN",
                receiverType: types.floatType,
                parameters: [],
                returnType: boolType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "isInfinite",
                externalLinkName: "kk_float_isInfinite",
                receiverType: types.floatType,
                parameters: [],
                returnType: boolType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "isFinite",
                externalLinkName: "kk_float_isFinite",
                receiverType: types.floatType,
                parameters: [],
                returnType: boolType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Double.toBits(): Long / Double.toRawBits(): Long
            registerSyntheticCoercionFunction(
                named: "toBits",
                externalLinkName: "kk_double_toBits",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "toRawBits",
                externalLinkName: "kk_double_toRawBits",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Float.toBits(): Int / Float.toRawBits(): Int
            registerSyntheticCoercionFunction(
                named: "toBits",
                externalLinkName: "kk_float_toBits",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoercionFunction(
                named: "toRawBits",
                externalLinkName: "kk_float_toRawBits",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )
        }

        // Int.countOneBits() / countLeadingZeroBits() / countTrailingZeroBits() (STDLIB-501)
        // STDLIB-BIT-007: Additional bit manipulation functions
        // Use if-let instead of guard-return so future registrations below are not skipped.
        if let kotlinPackageSymbol = symbols.lookup(fqName: kotlinPkg) {
            registerSyntheticCoercionFunction(
                named: "countOneBits",
                externalLinkName: "kk_int_countOneBits",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "countLeadingZeroBits",
                externalLinkName: "kk_int_countLeadingZeroBits",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "countTrailingZeroBits",
                externalLinkName: "kk_int_countTrailingZeroBits",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // STDLIB-BIT-007: Additional bit manipulation functions

            // Zero-argument Int functions
            registerSyntheticCoercionFunction(
                named: "highestOneBit",
                externalLinkName: "kk_int_highestOneBit",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "lowestOneBit",
                externalLinkName: "kk_int_lowestOneBit",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "takeHighestOneBit",
                externalLinkName: "kk_int_takeHighestOneBit",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "takeLowestOneBit",
                externalLinkName: "kk_int_takeLowestOneBit",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Int rotation functions
            registerSyntheticCoercionFunction(
                named: "rotateLeft",
                externalLinkName: "kk_int_rotateLeft",
                receiverType: types.intType,
                parameters: [("distance", types.intType)],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "rotateRight",
                externalLinkName: "kk_int_rotateRight",
                receiverType: types.intType,
                parameters: [("distance", types.intType)],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Zero-argument Long functions
            registerSyntheticCoercionFunction(
                named: "highestOneBit",
                externalLinkName: "kk_long_highestOneBit",
                receiverType: types.longType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "lowestOneBit",
                externalLinkName: "kk_long_lowestOneBit",
                receiverType: types.longType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "takeHighestOneBit",
                externalLinkName: "kk_long_takeHighestOneBit",
                receiverType: types.longType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "takeLowestOneBit",
                externalLinkName: "kk_long_takeLowestOneBit",
                receiverType: types.longType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Long rotation functions
            registerSyntheticCoercionFunction(
                named: "rotateLeft",
                externalLinkName: "kk_long_rotateLeft",
                receiverType: types.longType,
                parameters: [("distance", types.intType)],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "rotateRight",
                externalLinkName: "kk_long_rotateRight",
                receiverType: types.longType,
                parameters: [("distance", types.intType)],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // MARK: - Primitive Type Conversion Functions (STDLIB-PRIM-002)

            // Int conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_int_to_byte",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_int_to_short",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_int_to_int",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toLong",
                externalLinkName: "kk_int_to_long",
                receiverType: types.intType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toFloat",
                externalLinkName: "kk_int_to_float",
                receiverType: types.intType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toDouble",
                externalLinkName: "kk_int_to_double_bits",
                receiverType: types.intType,
                parameters: [],
                returnType: types.doubleType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toChar",
                externalLinkName: "kk_int_to_char",
                receiverType: types.intType,
                parameters: [],
                returnType: types.charType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUByte",
                externalLinkName: "kk_int_to_ubyte",
                receiverType: types.intType,
                parameters: [],
                returnType: types.ubyteType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUShort",
                externalLinkName: "kk_int_to_ushort",
                receiverType: types.intType,
                parameters: [],
                returnType: types.ushortType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_int_to_uint",
                receiverType: types.intType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_int_to_ulong",
                receiverType: types.intType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Long conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_long_to_byte",
                receiverType: types.longType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_long_to_short",
                receiverType: types.longType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_long_to_int",
                receiverType: types.longType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toFloat",
                externalLinkName: "kk_long_to_float",
                receiverType: types.longType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toDouble",
                externalLinkName: "kk_long_to_double",
                receiverType: types.longType,
                parameters: [],
                returnType: types.doubleType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toChar",
                externalLinkName: "kk_long_to_char",
                receiverType: types.longType,
                parameters: [],
                returnType: types.charType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUByte",
                externalLinkName: "kk_long_to_ubyte",
                receiverType: types.longType,
                parameters: [],
                returnType: types.ubyteType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUShort",
                externalLinkName: "kk_long_to_ushort",
                receiverType: types.longType,
                parameters: [],
                returnType: types.ushortType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_long_to_uint",
                receiverType: types.longType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_long_to_ulong",
                receiverType: types.longType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Float conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_float_to_int",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_float_to_int",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_float_to_int",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toLong",
                externalLinkName: "kk_float_to_long",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toDouble",
                externalLinkName: "kk_float_to_double_bits",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.doubleType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toChar",
                externalLinkName: "kk_float_to_char",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.charType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_float_to_uint",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_float_to_ulong",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Double conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_double_to_int",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_double_to_int",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_double_to_int",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toLong",
                externalLinkName: "kk_double_to_long",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toFloat",
                externalLinkName: "kk_double_to_float",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toChar",
                externalLinkName: "kk_double_to_char",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.charType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_double_to_uint",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_double_to_ulong",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Char conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_char_to_int",
                receiverType: types.charType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_char_to_int",
                receiverType: types.charType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_char_to_int",
                receiverType: types.charType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toLong",
                externalLinkName: "kk_char_to_long",
                receiverType: types.charType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_char_to_uint",
                receiverType: types.charType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_char_to_ulong",
                receiverType: types.charType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-NUM-130: Double.fromBits(bits: Long) and Float.fromBits(bits: Int)
        // Registered as top-level kotlin package functions (no receiver) so that the
        // numericCompanionFunction path in the type checker can resolve them.
        registerSyntheticTopLevelFunction(
            named: "fromBits",
            packageFQName: kotlinPkg,
            parameters: [(name: "bits", type: types.longType)],
            returnType: types.doubleType,
            externalLinkName: "kk_double_fromBits",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "fromBits",
            packageFQName: kotlinPkg,
            parameters: [(name: "bits", type: types.intType)],
            returnType: types.floatType,
            externalLinkName: "kk_float_fromBits",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        // Avoid duplicate registration (same signature).
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == nil
                && sig.parameterTypes == parameters.map(\.type)
                && sig.returnType == returnType
        }) {
            return
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticCoercionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]

        // Check if already registered with same signature
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }) {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for param in parameters {
            let paramName = interner.intern(param.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: functionSymbol
        )
    }
}
