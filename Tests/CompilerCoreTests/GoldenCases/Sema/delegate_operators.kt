package golden.sema

import kotlin.reflect.KProperty

// getValue operator: read from delegated property
class ReadOnlyDelegate {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = "delegated"
}

// setValue operator: write to delegated property
class ReadWriteDelegate {
    private var stored: String = ""
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = stored
    operator fun setValue(thisRef: Any?, property: KProperty<*>, value: String) {
        stored = value
    }
}

// provideDelegate operator: intercept delegation creation
class DelegateProvider {
    operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): ReadOnlyDelegate {
        return ReadOnlyDelegate()
    }
}

val readOnly: String by ReadOnlyDelegate()
var readWrite: String by ReadWriteDelegate()
val provided: String by DelegateProvider()
