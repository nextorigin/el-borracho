redis      = require "ioredis"
{expect}   = require "chai"
express    = require "express"
errify     = require "errify"
BullModel  = require "../src/bull-model"
qCleaner   = require "./q-cleaner"


queuename = "test"


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
      data      = {name: "testjob"}

      await instance.createJobInQueue queuename, data, ideally defer job
      queue = instance.queues[queuename]
      expect(queue).to.exist
      qCleaner(queue).asCallback done

    it "should add a job to a bull queue", (done) ->
      ideally   = errify done
      data      = {name: "testjob"}

      await instance.createJobInQueue queuename, data, ideally defer job
      queue = instance.queues[queuename]
      await queue.count().asCallback ideally defer count
      expect(count).to.equal 1
      qCleaner(queue).asCallback done


