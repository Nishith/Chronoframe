import ChronoframePackaging
import Foundation

let exitCode = BundleValidatorCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
Foundation.exit(exitCode)
