package golden.sema

class Validated {
    var `value`: Int = 0
        set(v) { field = if (v < 0) 0 else v }

    val doubled: Int
        get() = `value` * 2
}
