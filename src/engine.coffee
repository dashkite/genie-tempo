import * as Val from "@dashkite/joy/value"
import * as Arr from "@dashkite/joy/array"
import Events from "@dashkite/events"

Rule =
  make: ({ conditions, action }) ->
    { conditions, action }

  defaults:
    equal: Val.equal
    dump: ( state ) -> state
    clone: structuredClone

Rules =

  make: ( options ) ->
    { 
      Rule.defaults...
      options...
      rules: []
      conditions: {}
      actions: {}
      events: Events.create()
    }

  register: ( engine, rules ) ->
    engine.rules = Arr.cat engine.rules,
      for name, conditions of rules
        Rule.make
          name: name
          conditions: conditions.map ( name ) ->
            do ({ apply } = {}) ->
              if ( apply = engine.conditions[ name ])?
                { name, apply }
              else
                throw new Error "unknown condition:
                  #{ name }"
          action: do ({ apply } = {}) ->
            if ( apply = engine.actions[ name ])?
              { name, apply }
            else
              throw new Error "unknown action:
                #{ name }"
    
  run: ( engine, state ) ->
    await do ({ log, rule, saved, changed } = {}) ->
      log = engine.logger
      loop
        rule = engine.rules.find ({ conditions }) ->
          conditions.every ({ name, apply }) -> 
            result = apply state
            log.debug condition: { name, result }
            result
        if rule?
          log.debug action: rule.action.name
          saved = state
          state = engine.clone state
          await rule.action.apply state
          changed = !( engine.equal saved, state )
          log.debug { changed }
          log.debug 
            before: engine.dump saved
            after: engine.dump state
          if changed
            engine.events.dispatch "change", state
          else
            break
        else break
      state

Conditions =

  register: ( engine, conditions ) ->
    engine.conditions = { engine.conditions..., conditions... }

Actions =
  
  register: ( engine, actions ) ->
    engine.actions = { engine.actions..., actions... }

export { Rules, Rule, Conditions, Actions }