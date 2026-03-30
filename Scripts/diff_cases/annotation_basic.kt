annotation class MyLabel(val name: String = "default")

@MyLabel("hello")
class Foo

@MyLabel
class Bar

annotation class Marker

@Marker
class Baz

fun main() {
    val foo = Foo()
    val bar = Bar()
    val baz = Baz()
    println("annotation_basic ok")
}
