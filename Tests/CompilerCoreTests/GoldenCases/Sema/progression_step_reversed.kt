// RF-FIXTURE-013: Progression.step() and Progression.reversed() return the
// same concrete Progression type.

fun steppedProgression() {
    val stepped = CharProgression.fromClosedRange('a', 'h', 1).step(3)
    val checked: CharProgression = stepped
}

fun reversedProgression() {
    val reversed = IntProgression.fromClosedRange(1, 9, 2).reversed()
    val checked: IntProgression = reversed
}
