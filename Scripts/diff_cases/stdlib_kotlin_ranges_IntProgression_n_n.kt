fun acceptIntProgressionCompanion(companion: Any): Boolean = true

fun main() {
    println(acceptIntProgressionCompanion(IntProgression.Companion))
    println(IntProgression.fromClosedRange(1, 5, 2).toList())
}
