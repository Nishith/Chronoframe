import ChronoframeCLIKit
import Foundation

let exitCode = await ChronoframeCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
Foundation.exit(exitCode)
