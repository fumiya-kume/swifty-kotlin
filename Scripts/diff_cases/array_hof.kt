fun main() {
    val arr = arrayOf(1, 2, 3)
    
    // 基本的な高階関数
    println(arr.map { it * 2 })
    println(arr.filter { it > 1 })
    arr.forEach { print(it) }
    println()
    
    // インデックス付き関数
    println(arr.mapIndexed { index, value -> index * value })
    println(arr.filterIndexed { index, value -> index % 2 == 0 && value > 1 })
    
    // 変換関数
    println(arr.mapNotNull { if (it % 2 == 0) it * 10 else null })
    println(arr.flatMap { arrayOf(it, it * 10) })
    println(arr.filterNot { it == 2 })
    println(arr.filterNotNull())
    
    // 集約関数
    println(arr.reduce { acc, value -> acc + value })
    println(arr.reduceIndexed { index, acc, value -> acc + index * value })
    println(arr.fold(100) { acc, value -> acc + value })
    println(arr.foldIndexed(100) { index, acc, value -> acc + index * value })
    
    // 検索関数
    println(arr.find { it > 2 })
    println(arr.findLast { it > 1 })
    println(arr.first { it > 1 })
    println(arr.firstOrNull { it > 5 })
    println(arr.last { it < 3 })
    println(arr.lastOrNull { it < 0 })
    
    // 判定関数
    println(arr.all { it < 10 })
    println(arr.any { it > 2 })
    println(arr.none { it > 10 })
    println(arr.count { it % 2 == 0 })
    println(arr.count())
    
    // 空配列テスト
    val empty = emptyArray<Int>()
    println(empty.reduceOrNull { acc, value -> acc + value })
    println(empty.firstOrNull())
    println(empty.lastOrNull())
}
