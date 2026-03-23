val String.wordCount: Int get() = this.split(" ").size
val List<Int>.secondOrNull: Int? get() = if (size >= 2) this[1] else null
val Int.isEven: Boolean get() = this % 2 == 0
fun main() {
    println("hello world foo".wordCount)
    println(listOf(10, 20, 30).secondOrNull)
    println(emptyList<Int>().secondOrNull)
    println(4.isEven)
    println(7.isEven)
}
