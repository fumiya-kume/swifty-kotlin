package golden.sema

import kotlin.reflect.KProperty

class ResourceDelegate {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = "value"
    operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): ResourceDelegate = this
}

val resource: String by ResourceDelegate()
