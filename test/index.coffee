redis      = require "redis"
{expect}   = require "chai"
{spy}      = require "sinon"
express    = require "express"
errify     = require "errify"
ElBorracho = require "../src/el-borracho"
BullModel  = require "../src/bull-model"
RedisModel = require "../src/redis-model"


describe "ElBorracho", ->
  client   = null
  instance = null
  beforeEach ->
    client   = redis.createClient()
    instance = new ElBorracho redisClient: client

  afterEach ->
    client = null
    instance = null

  describe "##constructor", ->
    it "should throw an error unless redisClient is passed in", ->
      newInstance = -> new ElBorracho
      expect(newInstance).to.throw Error

    it "should initialize a RedisModel instance", ->
      expect(instance.store).to.be.an.instanceof RedisModel

    it "should initialize a BullModel instance", ->
      expect(instance.bull).to.be.an.instanceof BullModel

    it "should initialize an express.Router instance", ->
      expect(instance.router).to.exist

    it "should accept an express.Router instance", ->
      router   = new express.Router
      instance = new ElBorracho {redisClient: client, router}
      expect(instance.router).to.equal router

    it "should run #loadMiddleware", ->
      bond     = spy ElBorracho::, "loadMiddleware"
      instance = new ElBorracho redisClient: client
      bond.restore()
      expect(bond.called).to.be.true

    it "should run #bindRoutes", ->
      bond     = spy ElBorracho::, "bindRoutes"
      instance = new ElBorracho redisClient: client
      bond.restore()
      expect(bond.called).to.be.true


describe "BullModel", ->
  client   = null
  instance = null
  beforeEach ->
    client   = redis.createClient()
    instance = new BullModel client

  afterEach ->
    client = null
    instance = null

  describe "##constructor", ->
    it "should set redis on the model", ->
      expect(instance.redisClient).to.equal client

    it "should create an empty object to hold queues", ->
      expect(instance.queues).to.be.an "object"
      expect(instance.queues).to.be.empty

  describe "##client", ->
    it "should return @redisClient", ->
      expect(instance.client()).to.equal instance.redisClient

  describe "##createJobInQueue", ->
    it "should create a new bull queue if none exists", (done) ->
      ideally   = errify done
      queuename = "test"
      data      = {name: "testjob"}

      await instance.createJobInQueue queuename, data, ideally defer job
      queue = instance.queues[queuename]
      expect(queue).to.exist
      queue.empty().then(queue.close()).asCallback done

    it "should add a job to a bull queue", (done) ->
      ideally   = errify done
      queuename = "test"
      data      = {name: "testjob"}

      await instance.createJobInQueue queuename, data, ideally defer job
      queue = instance.queues[queuename]
      await queue.count().asCallback ideally defer count
      expect(count).to.equal 1
      queue.empty().then(queue.close()).asCallback done
