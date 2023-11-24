import assert from "@dashkite/assert"
import {test, success} from "@dashkite/amen"
import print from "@dashkite/amen-console"

do ->

  print await test "Genie Tempo", [

    test "todo"

  ]

  process.exit if success then 0 else 1
