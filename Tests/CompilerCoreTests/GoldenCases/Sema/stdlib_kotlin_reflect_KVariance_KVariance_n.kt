package golden.sema

import kotlin.reflect.KVariance

fun varianceEntries(): kotlin.enums.EnumEntries<KVariance> = KVariance.entries

fun varianceValues(): Array<KVariance> = KVariance.values()

fun varianceValueOf(name: String): KVariance = KVariance.valueOf(name)
