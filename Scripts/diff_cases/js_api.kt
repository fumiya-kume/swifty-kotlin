// SKIP-DIFF
// JS-specific API smoke test (STDLIB-JS-167)
// This file exercises the Kotlin/JS annotations and types so that the compiler
// can parse, type-check, and lower them on native targets.
// @JsName / @JsExport / @JsModule are Kotlin/JS-only annotations and are not
// available in the standard kotlinc JVM backend, so this file is excluded from
// the kotlinc diff regression test.

@JsName("myRenamedFunction")
fun namedFunction(): String = "renamed"

@JsExport
class ExportedClass {
    val value: Int = 42

    @JsName("computeDouble")
    fun compute(): Int = value * 2
}

@JsModule("some-npm-package")
@JsName("SomeExternalClass")
external class ExternalClass {
    fun doSomething(): String
}

fun main() {
    // @JsName / @JsExport / @JsModule annotations are parsed and type-checked
    val exported = ExportedClass()
    println(exported.value)   // 42
    println(exported.compute()) // 84

    // Named function is callable
    println(namedFunction()) // renamed

    println("js_api ok")
}
