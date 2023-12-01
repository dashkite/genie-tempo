import process from "node:process"
import Path from "node:path"
import Zephyr from "@dashkite/zephyr"
import { command as exec } from "execa"
import { generic } from "@dashkite/joy/generic"
import * as Type from "@dashkite/joy/type"
import * as Arr from "@dashkite/joy/array"
import log from "./logger"

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
    args ?= []
    if ( script = await Scripts.find name )?
      Scripts.expand script, args
    else
      throw new Error "genie-tempo:
        script #{ name } not found"

  run: ({ script, args, cwd }) ->
    log.debug run: { script, cwd }
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
  # TODO can we assume package.json is always in the root?
  load: ( name ) -> Zephyr.read Path.join name, "package.json"

XRL =
  from : ( value ) ->
    try
      new URL value

Dependencies =

  normalize: ( repos, dependencies = []) ->
    Object.values dependencies
      .map XRL.from
      .filter ( url ) -> url?
      # TODO check to be sure the path references cwd
      #      we'd have to resolve relative to 
      #      package.json directory
      .map ( url ) -> Path.basename url.pathname
      .map ( name ) -> 
        repos.find ( repo ) -> repo.name == name
      .filter ( repo ) -> repo?

# import * as TK from "terminal-kit"

# progress = ({ count }, f) ->
#   bar = TK.terminal.progressBar
#     title: "Progress"
#     percent: true
#     eta: true
#     barChar: "◼︎"
#     barHeadChar: "◼︎"
#   counter = 0
#   await f increment: -> bar.update ++counter / count
#   TK.terminal "\n"

export { Scripts, Script, Repos, Repo, Rules, Package, 
  XRL, Dependencies }