package golden.parser

class Person(val name: String, val age: Int)

class Animal(val species: String) {
    constructor(species: String, name: String) : this(species) {
        val tag = name
    }
}
