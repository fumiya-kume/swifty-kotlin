fun main() {
    val list = listOf(1, 2, 3, 4)
    // foldRight: ((1, (2, (3, (4, ""))))) → "1234"
    val result = list.foldRight("") { item, acc -> "$item$acc" }
    println(result)  // 1234

    val sum = list.foldRight(0) { item, acc -> item + acc }
    println(sum)  // 10

    // foldRightIndexed
    val indexed = list.foldRightIndexed("") { idx, item, acc -> "[$idx:$item]$acc" }
    println(indexed)  // [0:1][1:2][2:3][3:4]
}
