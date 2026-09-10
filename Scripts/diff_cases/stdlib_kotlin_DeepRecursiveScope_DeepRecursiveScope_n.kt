// KSP-827: DeepRecursiveScope.callRecursive preserves its suspend contract.

val recursive = DeepRecursiveFunction<Int, Int> { value ->
    if (value <= 0) 0 else value + callRecursive(value - 1)
}

fun main() {
    println(recursive(5))
}
