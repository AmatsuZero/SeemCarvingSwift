@_exported import SeamCarvingAppleCLIBackend
@_exported import SeamCarvingCLIArguments
@_exported import SeamCarvingCLIModel
@_exported import SeamCarvingCLIOrchestration

@available(*, deprecated, message: "Import SeamCarvingCLIArguments and use CLIArgumentParser.parseOptions(_:).")
public extension CLIOptions {
    static func parse(_ arguments: [String]) throws -> CLIOptions {
        try CLIArgumentParser.parseOptions(arguments)
    }
}

@available(*, deprecated, message: "Import SeamCarvingCLIArguments and use CLIArgumentParser.parseConfiguration(_:).")
public extension CLIConfiguration {
    static func parse(arguments: [String]) throws -> CLIConfiguration {
        try CLIArgumentParser.parseConfiguration(arguments)
    }

    static func parse(parsedArguments: CLIParsedArguments) throws -> CLIConfiguration {
        try CLIArgumentParser.configuration(from: parsedArguments)
    }
}
