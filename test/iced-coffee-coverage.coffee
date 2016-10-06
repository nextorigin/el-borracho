# https://github.com/benbria/coffee-coverage/blob/master/docs/HOWTO-istanbul.md#writing-a-custom-loader
path           = require "path"
coffeeCoverage = require "iced-coffee-coverage"


projectRoot = path.resolve __dirname, "../"
coverageVar = coffeeCoverage.findIstanbulVariable()
# Only write a coverage report if we're not running inside of Istanbul.
writeOnExit = unless coverageVar? then "#{projectRoot}/coverage/coverage-coffee.json" else null

coffeeCoverage.register
  instrumentor: "istanbul"
  basePath:     projectRoot
  exclude: [
    "/test"
    "/node_modules"
    "/.git"
    "/*.coffee"
    "/helpers"
  ]
  coverageVar:  coverageVar
  writeOnExit:  writeOnExit
  initAll:      true
