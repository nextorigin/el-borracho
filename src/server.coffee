require "source-map-support/register"
Redis    = require "redis"
path     = require "path"
Skeleton = require "nextorigin-express-skeleton"
Borracho = require "./router"


uiPath = path.join __dirname, "../", "node_modules", "el-borracho-ui", "public"


class ElBorrachoServer extends Skeleton
  constructor: (options = {}) ->

    @redis  = Redis.createClient()
    {@ui}   = options
    options.address = "0.0.0.0"

    if process.env.NODE_ENV is "production"
      oneYear = 86400
      options.static = root: uiPath, options: maxAge: oneYear
    else
      options.static = uiPath

    super options
    @debug "initializing"

  bindRoutes: ->
    @borracho = new Borracho {@redis}
    if @ui
      @app.use "/jobs", @borracho.router
      @app.get "/", (req, res, next) -> res.sendFile path.join uiPath, "index.html"
    else
      @app.use "/", @borracho.router

ebs = new ElBorrachoServer
ebs.listen()

