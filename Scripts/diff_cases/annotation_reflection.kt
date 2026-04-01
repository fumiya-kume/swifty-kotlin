// STDLIB-REFLECT-065: Annotation reflection
annotation class MyLabel(val name: String = "default")
annotation class Marker

@MyLabel("hello")
@Marker
class Foo

@MyLabel
class Bar

class Baz

fun main() {
    // KClass.annotations — returns a list of annotations
    val fooAnnotations = Foo::class.annotations
    println(fooAnnotations.size) // 2

    val barAnnotations = Bar::class.annotations
    println(barAnnotations.size) // 1

    val bazAnnotations = Baz::class.annotations
    println(bazAnnotations.size) // 0

    println("annotation_reflection ok")
}
