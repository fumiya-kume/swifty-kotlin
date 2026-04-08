fun main() {
    val range = 1..10
    println(range.take(3))   // [1, 2, 3]
    println(range.drop(7))   // [8, 9, 10]
    println(range.take(0))   // []
    println(range.drop(20))  // []
    println((1..5).average())  // 3.0
    println((1..5).sorted())   // [1, 2, 3, 4, 5]
}
