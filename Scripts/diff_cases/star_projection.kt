class Box<T>

fun accept(box: Box<*>) {
    println("accept")
}

fun main() {
    accept(Box<Int>())
    accept(Box<String>())
}
