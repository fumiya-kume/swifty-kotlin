extension CodegenPhase {
    func llvmCapiBackendUsableForDefaultSelection(target: TargetTriple) -> Bool {
        guard let bindings = LLVMCAPIBindings.load(),
              bindings.smokeTestContextLifecycle()
        else {
            return false
        }

        let requestedTriple = targetTripleString(target)
        if canCreateTargetMachine(bindings: bindings, triple: requestedTriple) {
            return true
        }

        guard let hostTriple = bindings.defaultTargetTriple(),
              !hostTriple.isEmpty,
              hostTriple != requestedTriple
        else {
            return false
        }
        return canCreateTargetMachine(bindings: bindings, triple: hostTriple)
    }

    func canCreateTargetMachine(
        bindings: LLVMCAPIBindings,
        triple: String
    ) -> Bool {
        guard let machine = bindings.createTargetMachine(triple: triple, optLevel: .O0) else {
            return false
        }
        bindings.disposeTargetMachine(machine)
        return true
    }

    func targetTripleString(_ target: TargetTriple) -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }
}
