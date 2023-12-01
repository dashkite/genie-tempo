import Util from "node:util"
import * as Fn from "@dashkite/joy/function"
import * as Type from "@dashkite/joy/type"
import * as Meta from "@dashkite/joy/metaclass"
import { Script, Repos, Repo, Rules, Package,
  Dependencies, Progress } from "./helpers"
import { Rules as Engine, Rule, Conditions, Actions } from "./engine"
# import log from "./helpers/logger"
import * as log from "@dashkite/kaiko"
import FS from "node:fs"

peek = ( stack ) -> stack[ 0 ]
push = ( stack, value ) -> stack.unshift value ; value
pop = ( stack ) -> stack.shift()
remove = ( stack, target ) ->
  if ( index = stack.indexOf target ) > -1
    stack.splice index, 1
rotate = ( stack ) -> stack.push stack.shift()
sort = ( stack ) -> 
  stack.sort ( a, b ) ->
    _a = a.score - ( a.failures * 10 )
    _b = b.score - ( b.failures * 10 )
    if _a <= _b then 1 else -1

# simple shallow array<repo> comparison
equal = ( a, b ) ->
  ( a.length == b.length  ) &&
    do ->
      for item, i in a
        return false if b[ i ].name != item.name
      true

rules = Engine.make

  equal: ( a, b ) ->
    ( equal a.built, b.built ) &&
      ( equal a.ready, b.ready ) &&      
      ( equal a.scheduled, b.scheduled ) &&
      ( equal a.pending, b.pending )

  dump: ( state ) ->
    pending: state.pending[ 0 ]?.name
    scheduled: state.scheduled[ 0 ]?.name
    built: state.built[ 0 ]?.name
    ready: state.ready[ 0 ]?.name
    development: state.development[ 0 ]?.name
  
  logger: log

Conditions.register rules,

  "nothing scheduled": ({ scheduled }) -> !( peek scheduled )?

  "has scheduled": ({ scheduled }) -> ( peek scheduled )?

  "has pending": ({ pending }) -> pending.length > 0

  "nothing pending":  ({ pending }) -> pending.length == 0

  "is built": ({ scheduled, built }) ->
    ( peek scheduled ) in built

  "is development dependency":
    ({ scheduled, development }) ->
      ( peek scheduled ) in development
  
  "is production dependency":
    ({ scheduled, development }) ->
      !(( peek scheduled ) in development )
  
  "all development dependencies are ready": 
    ({ scheduled, ready }) ->
      ( peek scheduled )
        ?.dependencies
        .development
        .every ( repo ) -> repo in ready

  "has development dependencies that aren't in flight":
    ({ scheduled, built }) ->
      current = peek scheduled
      current
        ?.dependencies
        .development
        .some ( repo ) ->
          !( repo in scheduled ) &&
            !( repo in built )

  "has production dependencies that aren't in flight":
    ({ scheduled, built }) ->
      ( peek scheduled )
        ?.dependencies
        .production
        .some ( repo ) -> 
          !( repo in scheduled ) &&
            !( repo in built )

  "all production dependencies are in flight":
    ({ scheduled, built }) ->
      ( peek scheduled )
        ?.dependencies
        .production
        .every ( repo ) -> 
          ( repo in scheduled ) ||
            ( repo in built )


  "all development dependencies are built":
    ({ scheduled, built }) ->
      repo = ( peek scheduled )
        ?.dependencies
        .development
        .every ( repo ) -> repo in built

  "all production dependencies are built":
    ({ scheduled, built }) ->
      repo = ( peek scheduled )
        ?.dependencies
        .production
        .every ( repo ) -> repo in built
  

  "not hopeless":
    ({ scheduled }) ->
      current = ( peek scheduled )
      current.failures <= 3

Actions.register rules,

  "select a target": 
    ({ scheduled, pending }) ->
      push scheduled, pop pending

  "find next development dependency":
    ({ built, scheduled, pending, development }) ->
      repo = ( peek scheduled )
        ?.dependencies
        .development
        .find ( repo ) ->
          repo.score++ if ( repo in scheduled ) 
          !( repo in scheduled ) &&
            !( repo in built )
      remove pending, repo
      push development, repo
      push scheduled, repo

  "find next production dependency":
    ({ built, scheduled, pending, development }) ->
      repo = ( peek scheduled )
        ?.dependencies
        .production
        .find ( repo ) ->
          !( repo in scheduled ) &&
            !( repo in built )
      remove pending, repo
      push development, repo
      push scheduled, repo

  "production dependency is built":
    ({ pending, scheduled, built, ready }) ->
      pop scheduled

  "development dependency is ready":
    ({ pending, scheduled, built, ready }) ->
      push ready, pop scheduled

  "development dependency is not ready":
    ({ scheduled }) -> 
      pop scheduled
      sort scheduled
  
  "build a target":
    ({ scheduled, built }) ->
      current = peek scheduled
      try
        await Script.run
          script: "build", 
          cwd: current.name
        log.debug built: current.name
        push built, peek scheduled
      catch error
        log.error error

  "try a new target":
    ({ scheduled, pending }) ->
      push scheduled, pop pending

  "attempt to build a target":
    ({ scheduled, built }) ->
      current = peek scheduled
      try
        await Script.run
          script: "build", 
          cwd: current.name
        log.debug built: current.name
        push built, peek scheduled
      catch
        # ignore error
        # reorder and hope for the best! :)
        current.failures++
        log.debug failures: current.failures
        sort scheduled

Engine.register rules,

  "select a target": [
    "nothing scheduled"
    "has pending"
  ]
        
  "find next development dependency": [
    "has scheduled"
    "has development dependencies that aren't in flight"
  ]

  "find next production dependency": [
    "has scheduled"
    "is development dependency"
    "has production dependencies that aren't in flight"
  ]
      
  "production dependency is built": [
    "has scheduled"
    "is production dependency"
    "is built"
  ]

  "development dependency is ready": [
    "has scheduled"
    "is development dependency"
    "is built"
    "all production dependencies are built"
  ]

  "development dependency is not ready": [
    "has scheduled"
    "is development dependency"
    "is built"
    "all production dependencies are in flight"
  ]

  "build a target": [
    "has scheduled"
    "all development dependencies are ready"
  ]

  "try a new target": [
    "has scheduled"
    "has pending"
  ]

  "attempt to build a target": [
    "has scheduled"
    "not hopeless"
  ]

initialize = ->
  $repos = ( repos = await do Repos.load )
  tagged = {}
  pending = []
  scheduled = []
  built = []
  ready = []
  development = []
  for repo in repos
    repo.pkg = await Package.load repo.name
    repo.dependencies =
      development: Dependencies.normalize repos, 
        repo.pkg.devDependencies
      production: Dependencies.normalize repos,
        repo.pkg.dependencies
    repo.failures = 0
    repo.score = 0
    pending.push repo
  if repo.tags?
    for tag in repo.tags
      tagged[ tag ] ?= []
      tagged[ tag ].push repo
  state = { repos, tagged, pending,
    scheduled, built, ready, development }
  state

run = ( tasks, options ) ->

  # configure logging
  if options.logfile?
    if options.verbose
      log.level "debug"
    else
      log.level "info"
    stream = FS.createWriteStream options.logfile
    log.pipe stream

  # initialize state
  state = await do initialize

  # set up progress bar
  if options.progress
    progress = Progress.make count: state.repos.length
    rules.events.on change: ( state ) ->
      progress.set state.built.length

  # actually run the rules
  state = await Engine.run rules, state

  # reporting
  log.debug status: "finished!"
  if state.built.length == state.repos.length
    log.debug success: 100
  else
    missing = []
    for repo in state.repos when !( repo in state.built )
      missing.push repo
    log.debug {
      success: state.built.length / state.repos.length
      built: state.built.length
      total: state.repos.length
      missing: missing.map ({ name, score, failures }) ->
        { name, score, failures }
    }
  
export { run }