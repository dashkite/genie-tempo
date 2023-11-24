import Zephyr from "@dashkite/zephyr"
import { command as exec } from "execa"

Scripts =

  load: -> Zephyr.read ".scripts.yaml"

  find: ( name ) ->
    scripts = await do Scripts.load
    scripts[ name ]

  expand: ( text, args ) ->
    text
      .replaceAll /\$(\d)/g, ( _, i ) ->
        if args[i]?
          args[i]
        else
          throw new Error "genie-tempo: 
            missing positional argument $#{i}"
      .replaceAll /\$@/g, -> args.join " "

Script = 

  prepare: ( name, args ) ->
    if ( script = await Scripts.find name )?
      Scripts.expand script, args
    else
      throw new Error "genie-tempo:
        script #{ name } not found"

  run: ({ script, args, cwd }) ->
    command = await Script.prepare script, args
    result = await exec command, 
      { stdout: "pipe", stderr: "pipe", shell: true, cwd }
    if result.exitCode != 0
      throw new Error result.stderr


Repos =

  load: -> Zephyr.read ".repos.yaml"

  find: ( name ) ->
    repos = await do Repos.load
    repos.find ( repo ) -> repo.name = name

Repo =

  run: ({ repo, script, args }) ->
    # ensure the repo exists
    if ( await Repos.find repo )?
      Script.run { script, args, cwd: repo }
    else
      throw new Error "genie-tempo:
        repo #{ repo } does not exist in this metarepo"

export { Scripts, Script, Repos, Repo }