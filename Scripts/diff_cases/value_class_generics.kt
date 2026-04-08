// SKIP-DIFF
@JvmInline
value class Box<T>(val value: T)

@JvmInline
value class IntBox(val value: Int)

fun <T> printBox(box: Box<T>) {
    println(box.value)
}

fun <T : Comparable<T>> maxOf(a: Box<T>, b: Box<T>): T {
    return if (a.value >= b.value) a.value else b.value
}

fun main() {
    val strBox = Box("hello")
    printBox(strBox)

    val intBox = Box(42)
    printBox(intBox)

    val a = Box(10)
    val b = Box(20)
    println(maxOf(a, b))

    val boxes: List<Box<Int>> = listOf(Box(3), Box(1), Box(2))
    val sorted = boxes.sortedBy { it.value }
    for (box in sorted) {
        println(box.value)
    }
}
