// Symmetric crypto functions (STDLIB-SEC-144).

public extension RuntimeABISpec {
    static let securityFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_secretkeyspec_new",
            parameters: [
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "algorithmRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ivparameterspec_new",
            parameters: [
                RuntimeABIParameter(name: "ivRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_getInstance",
            parameters: [
                RuntimeABIParameter(name: "transformationRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_init",
            parameters: [
                RuntimeABIParameter(name: "cipherRaw", type: .intptr),
                RuntimeABIParameter(name: "opmodeRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_init_with_iv",
            parameters: [
                RuntimeABIParameter(name: "cipherRaw", type: .intptr),
                RuntimeABIParameter(name: "opmodeRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "ivRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_doFinal",
            parameters: [
                RuntimeABIParameter(name: "cipherRaw", type: .intptr),
                RuntimeABIParameter(name: "dataRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cipher_doFinal_noarg",
            parameters: [
                RuntimeABIParameter(name: "cipherRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Security"
        ),
    ]
}
