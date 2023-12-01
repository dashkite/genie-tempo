import FS from "node:fs"
import Path from "node:path"
import { program } from "commander"
import { run } from "./rules"

pkg = do ({ path, json, pkg } = {}) ->
  path = Path.join __dirname, "..", "..", "..", "package.json"
  json = FS.readFileSync path, "utf8"
  JSON.parse json

program
  .version pkg.version
  .enablePositionalOptions()
  .description "build and deployment manager"
  # .option "-l, --list", "List commands"
  # .option "-x, --exclude <presets...>", 
  #   "Exclude a preset from auto-loaded"
  # .option "-c, --halt", "Halt if a cycle is detected"
  # .option "-p, --progress", "Show progress bar"
  .argument "[tasks...]", "Tasks to run"
  .action run

program.parseAsync()
