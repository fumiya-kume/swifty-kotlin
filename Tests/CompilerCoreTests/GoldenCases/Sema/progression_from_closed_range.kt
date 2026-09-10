// RF-FIXTURE-013: XxxProgression.fromClosedRange fixes the companion factory
// argument types and the concrete Progression return type for all five
// progression element types. Element enumeration, endpoints and step values
// are executed by Scripts/diff_cases/progression.kt.

fun intProgression() {
    val progression = IntProgression.fromClosedRange(1, 10, 2)
    val checked: IntProgression = progression
}

fun longProgression() {
    val progression = LongProgression.fromClosedRange(1L, 10L, 3)
    val checked: LongProgression = progression
}

fun charProgression() {
    val progression = CharProgression.fromClosedRange('a', 'g', 2)
    val checked: CharProgression = progression
}

fun uintProgression() {
    val progression = UIntProgression.fromClosedRange(1u, 10u, 2)
    val checked: UIntProgression = progression
}

fun ulongProgression() {
    val progression = ULongProgression.fromClosedRange(1UL, 10UL, 3)
    val checked: ULongProgression = progression
}
