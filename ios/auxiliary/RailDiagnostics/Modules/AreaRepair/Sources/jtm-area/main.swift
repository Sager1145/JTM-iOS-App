import Foundation
import AreaKit

// Placeholder entry point; the CLI verbs are implemented by a later unit.
let usage = """
usage: jtm-area <capture-data|problems|apply|preview|write|undo|guard> [options]
  (not implemented yet in this build)
"""
FileHandle.standardError.write(Data((usage + "\n").utf8))
exit(64)
