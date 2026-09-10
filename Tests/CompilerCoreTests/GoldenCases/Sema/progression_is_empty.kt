// RF-FIXTURE-013: Progression.isEmpty() returns Boolean (checked on a
// degenerate range, matching the original fixture's scenario).

fun emptyProgression() {
    val empty = IntProgression.fromClosedRange(10, 1, 1).isEmpty()
    val checked: Boolean = empty
}
