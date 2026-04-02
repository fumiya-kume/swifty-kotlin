// STDLIB-REFLECT-065: Annotation Reflection
// Tests annotation metadata access via KClass reflection APIs.

@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
annotation class MyAnnotation(val value: String = "default")

@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
annotation class AnotherAnnotation

@MyAnnotation(value = "hello")
@AnotherAnnotation
class AnnotatedClass

class UnannotatedClass

fun main() {
    val klass = AnnotatedClass::class
    val annotations = klass.annotations
    println("annotation count: ${annotations.size}")

    val found = klass.findAnnotation<MyAnnotation>()
    if (found != null) {
        println("found MyAnnotation")
    } else {
        println("MyAnnotation not found")
    }

    val notFound = klass.findAnnotation<AnotherAnnotation>()
    if (notFound != null) {
        println("found AnotherAnnotation")
    } else {
        println("AnotherAnnotation not found")
    }

    val unannotated = UnannotatedClass::class
    println("unannotated count: ${unannotated.annotations.size}")
}
