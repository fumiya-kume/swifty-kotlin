public extension RuntimeABISpec {
    static let kotlinVersionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_kotlin_version_new",
            parameters: [
                RuntimeABIParameter(name: "major", type: .intptr),
                RuntimeABIParameter(name: "minor", type: .intptr),
            ],
            returnType: .intptr,
            section: "KotlinVersion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kotlin_version_new_patch",
            parameters: [
                RuntimeABIParameter(name: "major", type: .intptr),
                RuntimeABIParameter(name: "minor", type: .intptr),
                RuntimeABIParameter(name: "patch", type: .intptr),
            ],
            returnType: .intptr,
            section: "KotlinVersion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kotlin_version_current",
            parameters: [],
            returnType: .intptr,
            section: "KotlinVersion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kotlin_version_major",
            parameters: [
                RuntimeABIParameter(name: "versionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "KotlinVersion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kotlin_version_minor",
            parameters: [
                RuntimeABIParameter(name: "versionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "KotlinVersion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kotlin_version_patch",
            parameters: [
                RuntimeABIParameter(name: "versionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "KotlinVersion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kotlin_version_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "KotlinVersion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kotlin_version_isAtLeast",
            parameters: [
                RuntimeABIParameter(name: "versionRaw", type: .intptr),
                RuntimeABIParameter(name: "major", type: .intptr),
                RuntimeABIParameter(name: "minor", type: .intptr),
            ],
            returnType: .intptr,
            section: "KotlinVersion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kotlin_version_isAtLeast_patch",
            parameters: [
                RuntimeABIParameter(name: "versionRaw", type: .intptr),
                RuntimeABIParameter(name: "major", type: .intptr),
                RuntimeABIParameter(name: "minor", type: .intptr),
                RuntimeABIParameter(name: "patch", type: .intptr),
            ],
            returnType: .intptr,
            section: "KotlinVersion"
        ),
    ]
}
