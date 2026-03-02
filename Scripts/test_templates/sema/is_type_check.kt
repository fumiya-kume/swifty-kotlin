package golden.sema

fun basicIs(v: Any): Boolean = v is String

fun negatedIs(v: Any): Boolean = v !is Int

fun smartCastAfterIs(v: Any): Int {
    if (v is String) {
        return v.length
    }
    return 0
}

fun combinedCondition(v: Any): String {
    if (v is String && v.length > 3) {
        return v
    }
    return ""
}

fun smartCastAfterNegatedIs(v: Any): Int {
    if (v !is String) {
        return 0
    } else {
        return v.length
    }
}

fun combinedOrCondition(v: Any): String {
    if (v !is String || v.length == 0) {
        return ""
    }
    return v
}
