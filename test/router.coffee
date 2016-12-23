http       = require "http"
Redis      = require "ioredis"
{expect}   = require "chai"
{spy}      = require "sinon"
express    = require "express"
Tubes      = require "sseries-of-tubes"
ElBorracho = require "../src/el-borracho"
Router     = require "../src/router"
RedisModel = require "../src/redis-model"


describe "ElBorrachoRouter", ->
  server   = null
  redis    = null
  instance = null

  beforeEach ->
    server   = new http.Server()
    redis    = Redis.createClient()
    instance = new Router {server, redis}

  afterEach ->
    server   = null
    redis    = null
    instance = null

  describe "##constructor", ->
    it "should initialize a SSEritesOfTubes instance", ->
      expect(instance.tubes).to.be.an.instanceof Tubes

    it "should initialize a ElBorracho instance", ->
      expect(instance.borracho).to.be.an.instanceof ElBorracho

    it "should initialize an express.Router instance", ->
      expect(instance.router).to.exist

    it "should accept an express.Router instance", ->
      router   = new express.Router
      instance = new Router {server, redis, router}
      expect(instance.router).to.equal router

    it "should default this.mount to /jobs", ->
      expect(instance.mount).to.equal "/jobs"

    it "should accept a mount", ->
      mount    = "/test"
      instance = new Router {server, redis, mount}
      expect(instance.mount).to.equal mount

    it "should run #loadMiddleware", ->
      bond     = spy Router::, "loadMiddleware"
      instance = new Router {server, redis}
      bond.restore()
      expect(bond.called).to.be.true

    it "should run #bindRoutes", ->
      bond     = spy Router::, "bindRoutes"
      instance = new Router {server, redis}
      bond.restore()
      expect(bond.called).to.be.true


