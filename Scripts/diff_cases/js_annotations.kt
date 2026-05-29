// SKIP-DIFF: kotlin.js.* APIs are Kotlin/JS-only and not available in JVM kotlinc
@file:OptIn(
    kotlin.js.ExperimentalJsFileName::class,
    kotlin.js.ExperimentalJsReflectionCreateInstance::class,
    kotlin.js.collections.ExperimentalJsCollectionsApi::class
)
@file:kotlin.js.ExperimentalJsFileName("JsAnnotationsCase")

import kotlin.js.ExperimentalJsExport
import kotlin.js.ExperimentalJsStatic
import kotlin.js.collections.asJsMapView
import kotlin.js.collections.asJsReadonlyArrayView
import kotlin.js.collections.asJsSetView
import kotlin.reflect.createInstance

@ExperimentalJsExport
class ExportedBox(val value: Int = 7)

object JsHolder {
    @ExperimentalJsStatic
    fun message(): String = "js-annotations"
}

@OptIn(kotlin.js.collections.ExperimentalJsCollectionsApi::class)
fun collectionSummary(): String {
    val map = mutableMapOf("a" to 1, "b" to 2)
    val set = mutableSetOf("x", "y", "z")
    val list = listOf(1, 2, 3, 4)
    return "${map.asJsMapView().toMutableMap().size}:${set.asJsSetView().toMutableSet().size}:${list.asJsReadonlyArrayView().toList().size}"
}

@OptIn(kotlin.js.ExperimentalJsReflectionCreateInstance::class)
fun reflectionApiToken(): String {
    val symbolName = (::createInstance).name
    val instance = ExportedBox::class.createInstance()
    return "${ExportedBox::class.simpleName}:${symbolName}:${instance.value}"
}

fun main() {
    println(JsHolder.message())
    println(collectionSummary())
    println(reflectionApiToken())
}
