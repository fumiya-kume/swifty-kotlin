fun makeDeepRecursiveFunction(
    other: DeepRecursiveFunction<Int, Int>
): DeepRecursiveFunction<Int, Int> =
    DeepRecursiveFunction<Int, Int> { value -> other.callRecursive(value) }

fun main() {
    val base = DeepRecursiveFunction<Int, Int> { value -> value }
    println(makeDeepRecursiveFunction(base)(3))
}
