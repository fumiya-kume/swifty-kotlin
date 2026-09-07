package golden.sema

fun useDeepRecursiveFunction(
    other: DeepRecursiveFunction<Int, Int>
): DeepRecursiveFunction<Int, Int> =
    DeepRecursiveFunction<Int, Int> { value -> other.callRecursive(value) }
