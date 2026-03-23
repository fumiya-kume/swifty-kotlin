fun main() {
    val nums = listOf(10, 20, 30, 40, 50)

    // filterIndexed
    val evens = nums.filterIndexed { index, _ -> index % 2 == 0 }
    println(evens) // [10, 30, 50]

    // foldIndexed
    val weighted = nums.foldIndexed(0) { index, acc, value -> acc + value * index }
    println(weighted) // 0*10 + 1*20 + 2*30 + 3*40 + 4*50 = 0+20+60+120+200 = 400

    // reduceIndexed
    val reduced = nums.reduceIndexed { index, acc, value -> acc + value * index }
    println(reduced) // 10 + 20*1 + 30*2 + 40*3 + 50*4 = 10+20+60+120+200 = 410

    // reduceIndexedOrNull on non-empty list
    val result = nums.reduceIndexedOrNull { index, acc, value -> acc + index }
    println(result) // 10 + 1 + 2 + 3 + 4 = 20

    // runningFoldIndexed
    val runFold = listOf(1, 2, 3).runningFoldIndexed(0) { index, acc, value -> acc + value * index }
    println(runFold) // [0, 0, 2, 8]

    // runningReduceIndexed
    val runReduce = listOf(1, 2, 3).runningReduceIndexed { index, acc, value -> acc + value * index }
    println(runReduce) // [1, 3, 9]

    // scanIndexed (alias of runningFoldIndexed)
    val scanned = listOf(1, 2, 3).scanIndexed(0) { index, acc, value -> acc + value * index }
    println(scanned) // [0, 0, 2, 8]
}
