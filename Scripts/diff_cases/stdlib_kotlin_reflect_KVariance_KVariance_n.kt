import kotlin.reflect.KVariance

fun main() {
    println(KVariance.entries.size)
    println(KVariance.entries[0])
    println(KVariance.values().size)
    println(KVariance.values()[2])
    println(KVariance.valueOf("IN"))

    try {
        KVariance.valueOf("MISSING")
        println("missing-error")
    } catch (_: IllegalArgumentException) {
        println("invalid-name")
    }
}
