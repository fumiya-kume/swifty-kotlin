package golden.sema

fun useDeepRecursiveScope(): DeepRecursiveFunction<Int, Int> =
    DeepRecursiveFunction<Int, Int> { value ->
        if (value <= 0) 0 else value + callRecursive(value - 1)
    }
