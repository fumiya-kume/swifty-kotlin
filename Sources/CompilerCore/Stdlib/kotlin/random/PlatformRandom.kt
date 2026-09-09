package kotlin.random

import java.util.Random as JavaUtilRandom

// KSP-466: see java.util.Random (JavaUtilRandom.kt) for why these convert
// between the two Random representations via a wrapped delegate rather than a
// raw pointer passthrough.

public fun java.util.Random.asKotlinRandom(): kotlin.random.Random = this.delegate

public fun Random.asJavaRandom(): java.util.Random = JavaUtilRandom(this)
