import Path from "node:path"
import * as Fn from "@dashkite/joy/function"
import * as Type from "@dashkite/joy/type"
import * as Meta from "@dashkite/joy/metaclass"
import { Script, Repos, Repo, Rules, Package,
  Dependencies, Progress } from "./helpers"
import { Rules as Engine, Rule, Conditions, Actions } from "./engine"
# import log from "./helpers/logger"
import * as log from "@dashkite/kaiko"
import FS from "node:fs"
import FSP from "node:fs/promises"

split = ( path ) -> path.split Path.sep

getModule = ( path ) ->
  components = path[ 1.. ].split Path.sep
  i = components.lastIndexOf "node_modules"
  if i > 0
    if components[ i + 1 ].startsWith "@"
      components[ i + 2 ]
    else
      components[ i + 1 ]

peek = ( stack ) -> stack[ 0 ]
push = ( stack, value ) -> stack.unshift value ; value
pop = ( stack ) -> stack.shift()
remove = ( stack, target ) ->
  if ( index = stack.indexOf target ) > -1
    stack.splice index, 1
rotate = ( stack ) -> stack.push stack.shift()
promote = ( stack, target ) ->
  if target in stack
    remove stack, target
    push stack, target
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
    queue: state.queue[ 0 ]?.name
  
  logger: log

Conditions.register rules,

  "nothing scheduled": ({ scheduled }) -> !( peek scheduled )?

  "has scheduled": ({ scheduled }) -> ( peek scheduled )?

  "has pending": ({ pending }) -> pending.length > 0

  "nothing pending":  ({ pending }) -> pending.length == 0

  "has queued": ({ queue }) -> queue.length > 0

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
    ({ scheduled, built, queue }) ->
      current = peek scheduled
      current
        ?.dependencies
        .development
        .some ( repo ) ->
          !( repo in scheduled ) &&
            !( repo in built ) &&
              !( repo in queue )

  "has production dependencies that aren't in flight":
    ({ scheduled, built, queue }) ->
      ( peek scheduled )
        ?.dependencies
        .production
        .some ( repo ) -> 
          !( repo in scheduled ) &&
            !( repo in built ) &&
              !( repo in queue )

  "all production dependencies are in flight":
    ({ scheduled, built, queue }) ->
      ( peek scheduled )
        ?.dependencies
        .production
        .every ( repo ) -> 
          ( repo in scheduled ) ||
            ( repo in built ) ||
              ( repo in queue )


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
    ({ built, scheduled, pending, development, queue }) ->
      repo = ( peek scheduled )
        ?.dependencies
        .development
        .find ( repo ) ->
          !( repo in scheduled ) &&
            !( repo in built ) &&
              !( repo in queue )
      remove pending, repo
      push development, repo
      push scheduled, repo

  "find next production dependency":
    ({ built, scheduled, pending, development, queue }) ->
      repo = ( peek scheduled )
        ?.dependencies
        .production
        .find ( repo ) ->
          !( repo in scheduled ) &&
            !( repo in built ) &&
              !( repo in queue )
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
  
  "queue a target":
    ({ scheduled, queue }) ->
      push queue, pop scheduled
  
  "build queued targets":
    ({ built, queue }) ->
      console.log "build queued targets"
      console.log queue.map ({ name }) -> name
      Promise.all do -> 
        until queue.length == 0
          current = pop queue
          do ( current ) ->
            try
              await Script.run
                script: "build", 
                cwd: current.name
              log.debug built: current.name
              push built, current
            catch error
              log.error error

  "try a new target":
    ({ scheduled, pending }) ->
      push scheduled, pop pending

  "attempt to build a target":
    ({ repos, scheduled, built }) ->
      current = peek scheduled
      try
        await Script.run
          script: "build", 
          cwd: current.name
        log.debug built: current.name
        push built, peek scheduled
      catch error
        log.debug error
        current.failures++
        log.debug failures: current.failures
        if error.stderr?
          console.log "found error"
          { stderr } = error
          if stderr.startsWith "Error: Cannot find module"
            console.log "cannot find module"
            if ( matches = stderr.match /'([^']+)'/ )?
              console.log "has path"
              [ _, path ] = matches
              name = getModule path
              console.log repo: name
              repo = repos.find ( repo ) -> repo.name == name
              if repo?
                # effectively demote current
                rotate scheduled
                console.log "found repo"
                if repo in scheduled
                  console.log "promoting"
                  promote scheduled, repo
                  
                else
                  console.log "scheduling"
                  push scheduled, repo
              else
                console.log "missing module is not a repo"
                console.log error
                # yolo
                sort scheduled
            else
              console.log "unable to extract path"
              console.log error
              # yolo
              sort scheduled
          else
            console.log "not stderr attached to error"
            console.log error
            # yolo
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

  "queue a target": [
    "has scheduled"
    "all development dependencies are ready"
  ]

  "build queued targets": [
    "has queued"
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
  queue = []
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
  # baseline score, done after we've normalized deps
  for repo in repos
    repo.score = repos
      .filter ( _repo ) ->
        repo in _repo.dependencies.development
      .length
  sort repos
  if repo.tags?
    for tag in repo.tags
      tagged[ tag ] ?= []
      tagged[ tag ].push repo
  state = { repos, tagged, pending, scheduled,
    built, ready, development, queue }
  state

build = ( repo ) ->
  Script.run
    script: "build", 
    cwd: repo.name

run = ( tasks, options ) ->

  # configure logging
  if options.verbose
    log.level "debug"
  else
    log.level "info"
  if options.logfile?
    stream = FS.createWriteStream options.logfile
    log.pipe stream
  if options.follow
    log.observe ( event ) ->
      console.log event.data

  # initialize state
  state = await do initialize

  # set up progress bar
  if options.progress
    progress = Progress.make count: state.repos.length
    progress.set 0
  else
    progress = set: ->

  repos = state.repos.length
  built = 0
  failed = 0
  batch = 12 # max parallel builds
  round = 0
  groups = await do ->
    try
      JSON.parse await FSP.readFile ".groups", "utf8"
    catch
      []

  until ( repos - ( built + failed ) == 0 )
    log.debug round: round++
    remaining = repos - ( built + failed )
    batch = if remaining >= batch then batch else remaining
    await do ({ queue } = {}) ->
      queue = []
      for repo in state.repos when repo not in state.built
        log.debug queuing: repo.name
        push queue, repo
        if queue.length == batch
          groups.push group = []
          log.debug batch: batch
          await Promise.all do ->
            until queue.length == 0
              repo = pop queue
              log.debug building: repo.name
              do ( repo ) ->
                try
                  await build repo
                  push state.built, repo
                  group.push repo.name
                  log.debug success: repo.name
                  built = state.built.length
                  progress.set built
                catch
                  repo.failures++
                  log.debug failure: repo.name
                  # if repo.failures >= 3
                  #   console.log "too many failures for #{ repo.name }"
                  #   state.failed.push repo
                  #   failed = state.failed.length

  await FSP.writeFile ".groups", JSON.stringify groups
  
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