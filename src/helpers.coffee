import Zephyr from "@dashkite/zephyr"
import { command as exec } from "execa"
import { generic } from "@dashkite/joy/generic"
import * as Type from "@dashkite/joy/type"

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

  find: do ({ find } = {}) ->

    find = generic name: "Repos.find"

    has = ( key ) -> ( value ) -> value[ key ]?

    generic find, 
      ( has "name" ),
      ({ name }) ->
        repos = await do Repos.load
        repos.find ( repo ) -> repo.name == name

    generic find,
      ( has "tag" ),
      ({ tag }) ->
        repos = await do Repos.load
        repos.filter ( repo ) -> 
          repo.tags? && ( tag in repo.tags )
    find

Repo =

  run: ({ repo, script, args }) ->
    Script.run { script, args, cwd: repo.name }

Rules = 

  load: -> Zephyr.read ".rules.yaml"

Package =

  load: ( name ) -> Zephyr.read "#{ name }/package.json"

export { Scripts, Script, Repos, Repo, Rules, Package }