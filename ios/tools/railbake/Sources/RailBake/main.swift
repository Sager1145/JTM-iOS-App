import Foundation
import RailBakeKit

exit(RailBakeCommand.run(arguments: Array(CommandLine.arguments.dropFirst())) { print($0) })
