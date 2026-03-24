class Outer(val x: Int) {
    class Nested {
        fun greet(): String {
            return "I am nested"
        }
    }
    inner class Inner {
        fun greet(): String {
            return "I see x=$x"
        }
    }
}
fun main() {
    println(Outer.Nested().greet())
    println(Outer(42).Inner().greet())
}
