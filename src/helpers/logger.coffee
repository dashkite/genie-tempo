class Logger

  @levels:
    info: 0
    warn: 1
    error: 2
    debug: 3

  @make: ({ level }) ->
    Object.assign ( new @ ), { level, _: [] }

  log: ( level, value ) ->
    if Logger.levels[ level ] <= Logger.levels[ @level ]
      @_.push value
    @

  info: ( value ) -> @log "info", value
  warn: ( value ) -> @log "warn", value
  error: ( value ) -> @log "error", value 
  debug: ( value ) -> @log "debug", value

  toJSON: -> JSON.stringify @_

  dump: -> console.log @toJSON()

log = Logger.make level: "error"

export default log