package golden.sema

fun useIt(): List<Int> = listOf(1, 2, 3).map { it * 2 }

fun useDestructuring(): List<Int> =
    listOf(1 to "a", 2 to "b").map { (num, _) -> num }
