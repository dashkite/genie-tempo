import { Scripts, Repos, Repo, Rules, Package } from "./helpers"
import Path from "node:path"

Task =

  bg: ( task ) -> "#{ task }&"

  build:

    repo: ({ repo, script }) ->
      "tempo:repo:#{ repo.name }:#{ script }"

    tag: ({ tag, script }) ->
      "tempo:tag:#{ tag }:#{ script }"

    dependencies: ({ repo, script }) ->
      "tempo:repo:#{ repo.name }:dependencies:#{ script }"

    devDependencies: ({ repo, script }) ->
      "tempo:repo:#{ repo.name }:dev-dependencies:#{ script }"

  run: ( rule ) ->
    if Array.isArray rule.run
      rule.run.map ( dependency ) -> "tempo:#{ dependency }"
    else "tempo:#{ rule.run }"

XRL =
  from : ( value ) ->
    try
      new URL value


export default ( genie ) ->

  tagged = {}
  repos = await do Repos.load
  scripts = Object.keys await do Scripts.load
  rules = await do Rules.load
  for repo in repos
    for script in scripts
      do ( repo, script ) ->
        genie.define ( Task.build.repo { repo, script }), 
          ( args... ) -> Repo.run { repo, script, args }  
    if repo.tags?
      for tag in repo.tags
        tagged[ tag ] ?= []
        tagged[ tag ].push repo

  for tag, _repos of tagged
    for script in scripts
      genie.define ( Task.build.tag { tag, script }),
        for repo in _repos
          Task.bg ( Task.build.repo { repo, script })

  devDependencies = {}

  for repo in repos
    pkg = await Package.load repo.name
    dependencies = []
    for name, specifier of pkg.devDependencies
      if ( url = XRL.from specifier )?      
        name = Path.join "./#{ repo.name }", url.pathname
        unless name.startsWith "."
          if ( dependency = await Repos.find { name })?
            devDependencies[ dependency.name ] = dependency
            dependencies.push Task.build.repo
              repo: dependency
              script: "build"
    if dependencies.length > 0
      genie.define ( Task.build.devDependencies { repo, script: "build"}), 
        dependencies
      genie.on ( Task.build.repo { repo, script: "build" } ),
        Task.build.devDependencies { repo, script: "build"}

  for repo in Object.values devDependencies
    pkg = await Package.load repo.name
    dependencies = []
    for name, specifier of pkg.dependencies
      if ( url = XRL.from specifier )?      
        name = Path.join "./#{ repo.name }", url.pathname
        unless name.startsWith "."
          if ( dependency = await Repos.find { name })?
            dependencies.push Task.build.repo
              repo: dependency
              script: "build"
    if dependencies.length > 0
      genie.define ( Task.build.dependencies { repo, script: "build"}), 
        dependencies
      genie.on ( Task.build.repo { repo, script: "build" } ),
        Task.build.dependencies { repo, script: "build"}
  
  for rule in rules
    if rule.before?
      genie.before "tempo:#{ rule.before }", Task.run rule
    else if rule.on?
      genie.on "tempo:#{ rule.on }", Task.run rule
    else if rule.define
      genie.define "tempo:#{ rule.define }", Task.run rule
    