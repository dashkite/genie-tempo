import { Scripts, Repos, Repo, Rules } from "./helpers"

Task =
  bg: ( task ) -> "#{ task }&"

  build:
    repo: ({ repo, script }) ->
      "tempo:repo:#{ repo.name }:#{ script }"

    tag: ({ tag, script }) ->
      "tempo:tag:#{ tag }:#{ script }"

  run: ( rule ) ->
    if Array.isArray rule.run
      rule.run.map ( dependency ) -> "tempo:#{ dependency }"
    else "tempo:#{ rule.run }"

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

  for tag, repos of tagged
    for script in scripts
      genie.define ( Task.build.tag { tag, script }),
        for repo in repos
          Task.bg ( Task.build.repo { repo, script } )

  for rule in rules
    if rule.before?
      genie.before "tempo:#{ rule.before }", Task.run rule
    else if rule.on?
      genie.on rule.on, Task.run rule