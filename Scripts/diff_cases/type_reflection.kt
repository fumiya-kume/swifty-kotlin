// STDLIB-REFLECT-066: KType reflection — typeOf<T>(), isMarkedNullable, classifier, arguments
import kotlin.reflect.typeOf

fun main() {
    // typeOf<T>() returns a KType for a non-nullable type
    val stringType = typeOf<String>()
    println(stringType)

    // typeOf<T?>() returns a KType for a nullable type
    val nullableIntType = typeOf<Int?>()
    println(nullableIntType)

    // isMarkedNullable distinguishes nullable from non-nullable
    val nonNullType = typeOf<String>()
    val nullableType = typeOf<String?>()
    println(nonNullType.isMarkedNullable)   // false
    println(nullableType.isMarkedNullable)  // true

    // classifier returns the KClass for the type
    val intType = typeOf<Int>()
    val classifier = intType.classifier
    println(classifier != null)  // true

    // arguments returns the type argument list (empty for non-generic types)
    val argsList = intType.arguments
    println(argsList)
}
