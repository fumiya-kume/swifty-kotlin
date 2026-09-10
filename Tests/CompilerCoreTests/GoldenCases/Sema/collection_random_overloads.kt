// RF-FIXTURE-016: Collection.random / randomOrNull — with and without a
// Random argument.
package golden.sema

import kotlin.random.Random

fun collectionRandom(values: Collection<Int>, seeded: Random) {
    val random = values.random()
    val checked: Int = random
    val randomSeeded = values.random(seeded)
    val checkedSeeded: Int = randomSeeded
    val randomOrNull = values.randomOrNull()
    val checkedOrNull: Int? = randomOrNull
    val randomOrNullSeeded = values.randomOrNull(seeded)
    val checkedOrNullSeeded: Int? = randomOrNullSeeded
}
