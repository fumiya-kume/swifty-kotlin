fun sample(flag: Boolean, x: Int): Int {
    return if (flag) {
        when (x) {
            1 -> 10
            else -> 20
        }
    } else {
        try x catch (e: Throwable) 0
    }
}
