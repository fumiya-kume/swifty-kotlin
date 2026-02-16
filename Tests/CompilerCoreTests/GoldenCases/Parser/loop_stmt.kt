fun loops(flag: Boolean, items: IntArray): Int {
    while (flag) { break }
    do { continue } while (flag)
    for (item in items) { break }
    return 1
}
