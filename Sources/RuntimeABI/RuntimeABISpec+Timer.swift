// Timer (java.util.Timer / kotlin.concurrent.schedule — STDLIB-CONC-FN-005)

public extension RuntimeABISpec {
    static let timerFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_schedule_delay",
            parameters: [
                RuntimeABIParameter(name: "timerRaw", type: .intptr),
                RuntimeABIParameter(name: "delayMs", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Timer"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_schedule_period",
            parameters: [
                RuntimeABIParameter(name: "timerRaw", type: .intptr),
                RuntimeABIParameter(name: "delayMs", type: .intptr),
                RuntimeABIParameter(name: "periodMs", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Timer"
        ),
    ]
}
