package golden.sema

class Foo(val x: Int) {
    companion object {
        const val MAX_COUNT: Int = 100
        fun create(): Foo = Foo(0)
    }
}

fun main() {
    val f: Foo = Foo.create()
    val m: Int = Foo.MAX_COUNT
}
