import Foundation

extension LLVMCAPIBindings {
    func defaultTargetTriple() -> String? {
        guard let triplePtr = getDefaultTargetTripleFn() else {
            return nil
        }
        defer { disposeMessageFn(triplePtr) }
        return String(cString: triplePtr)
    }

    func createTargetMachine(triple: String, optLevel: OptimizationLevel) -> LLVMTargetMachineRef? {
        initializeTarget(for: triple)

        var target: LLVMTargetRef?
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = triple.withCString { getTargetFromTripleFn($0, &target, &errorMessage) }
        if status != 0 {
            if let errorMessage {
                disposeMessageFn(errorMessage)
            }
            return nil
        }

        let opt = llvmOptLevel(optLevel)
        let reloc: UInt32 = 0
        let codeModel: UInt32 = 0
        return triple.withCString { tripleCStr in
            "generic".withCString { cpuCStr in
                "".withCString { featuresCStr in
                    createTargetMachineFn(target, tripleCStr, cpuCStr, featuresCStr, opt, reloc, codeModel)
                }
            }
        }
    }

    func disposeTargetMachine(_ machine: LLVMTargetMachineRef?) {
        disposeTargetMachineFn(machine)
    }

    func applyTargetMachine(_ machine: LLVMTargetMachineRef?, to module: LLVMModuleRef?) -> Bool {
        guard let machine, let module else {
            return false
        }
        guard let targetData = createTargetDataLayoutFn(machine) else {
            return false
        }
        defer { disposeTargetDataFn(targetData) }
        guard let layoutCString = copyStringRepOfTargetDataFn(targetData) else {
            return false
        }
        defer { disposeMessageFn(layoutCString) }
        setDataLayoutFn(module, layoutCString)
        return true
    }

    func emitObject(targetMachine: LLVMTargetMachineRef?, module: LLVMModuleRef?, outputPath: String) -> String? {
        guard let targetMachine, let module else {
            return "LLVM target machine is not initialized."
        }

        let mutablePath = strdup(outputPath)
        defer { free(mutablePath) }
        guard let mutablePath else {
            return "Unable to allocate output path buffer."
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = emitToFileFn(targetMachine, module, mutablePath, 1, &errorMessage)
        if status == 0 {
            return nil
        }
        defer {
            if let errorMessage {
                disposeMessageFn(errorMessage)
            }
        }
        if let errorMessage {
            return String(cString: errorMessage)
        }
        return "LLVMTargetMachineEmitToFile failed."
    }

    func initializeTarget(for triple: String) {
        if triple.hasPrefix("x86_64") || triple.hasPrefix("i386") {
            initializeX86TargetInfoFn?()
            initializeX86TargetFn?()
            initializeX86TargetMCFn?()
            initializeX86AsmPrinterFn?()
            return
        }
        if triple.hasPrefix("arm64") || triple.hasPrefix("aarch64") {
            initializeAArch64TargetInfoFn?()
            initializeAArch64TargetFn?()
            initializeAArch64TargetMCFn?()
            initializeAArch64AsmPrinterFn?()
        }
    }

    func llvmOptLevel(_ level: OptimizationLevel) -> UInt32 {
        switch level {
        case .O0:
            return 0
        case .O1:
            return 1
        case .O2:
            return 2
        case .O3:
            return 3
        }
    }
}
