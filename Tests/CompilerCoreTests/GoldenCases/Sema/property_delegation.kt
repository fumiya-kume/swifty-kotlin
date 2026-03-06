package golden.sema

class LazyHolder {
    val x: Int by lazy { 42 }
}

class CustomDelegate {
    operator fun getValue(thisRef: Any?, property: Any?): String = "hello"
    operator fun setValue(thisRef: Any?, property: Any?, `value`: String) {}
}

class Holder {
    val name: String by CustomDelegate()
    var mutable: String by CustomDelegate()
}
