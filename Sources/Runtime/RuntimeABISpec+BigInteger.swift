// BigInteger functions (STDLIB-NUM-129).

public extension RuntimeABISpec {
    static let bigIntegerFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_valueOf",
            parameters: [
                RuntimeABIParameter(name: "longValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_fromString",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_add",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_subtract",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_multiply",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_divide",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_gcd",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_abs",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_pow",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
                RuntimeABIParameter(name: "exponent", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_and",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_toInt",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_toLong",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_biginteger_toString",
            parameters: [
                RuntimeABIParameter(name: "self", type: .intptr),
            ],
            returnType: .intptr,
            section: "BigInteger"
        ),
    ]
}
