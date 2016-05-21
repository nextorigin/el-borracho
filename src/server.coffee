Redis    = require "redis"
Skeleton = require "nextorigin-express-skeleton"
Borracho = require "./express-bull"


class ElBorrachoServer extends Skeleton
  constructor: ->
    @redis = Redis.createClient()
    super address: "0.0.0.0"

  bindRoutes: ->
    @borracho = new Borracho redisClient: @redis
    @app.use "/jobs", @borracho.router
    @app.get "/", (req, res, next) -> res.sendFile path.join __dirname, "../", "public", "index.html"


ebs = new ElBorrachoServer
ebs.listen()

