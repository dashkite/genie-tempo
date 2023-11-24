import { Repo } from "./helpers"

export default ( genie ) ->

  genie.define "tempo", ( repo, script, args... ) ->
    Repo.run { repo, script, args }