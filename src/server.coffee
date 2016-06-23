Redis    = require "redis"
path     = require "path"
Skeleton = require "nextorigin-express-skeleton"
Borracho = require "./el-borracho"


class ElBorrachoServer extends Skeleton
  constructor: ->

    @redis  = Redis.createClient()
    options =
      address: "0.0.0.0"

    if process.env.NODE_ENV is "production"
      oneYear = 86400
      options.static = root: (path.join __dirname, "../", "public"), options: maxAge: oneYear
    else
      options.static = (path.join __dirname, "../", "public")

    super options
    @debug "initializing"

  bindRoutes: ->
    @borracho = new Borracho redisClient: @redis
    @app.use "/jobs", @borracho.router
    @app.get "/", (req, res, next) -> res.sendFile path.join __dirname, "../", "public", "index.html"


ebs = new ElBorrachoServer
ebs.listen()

