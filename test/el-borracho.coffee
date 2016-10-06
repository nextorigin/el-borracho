redis      = require "redis"
{expect}   = require "chai"
{spy}      = require "sinon"
express    = require "express"
ElBorracho = require "../src/el-borracho"
BullModel  = require "../src/bull-model"
RedisModel = require "../src/redis-model"


describe "ElBorracho", ->
  client   = null
  instance = null
  beforeEach ->
    client   = redis.createClient()
    instance = new ElBorracho redis: client

  afterEach ->
    client = null
    instance = null

  describe "##constructor", ->
    it "should throw an error unless redis is passed in", ->
      newInstance = -> new ElBorracho
      expect(newInstance).to.throw Error

    it "should initialize a RedisModel instance", ->
      expect(instance.store).to.be.an.instanceof RedisModel

    it "should initialize a BullModel instance", ->
      expect(instance.bull).to.be.an.instanceof BullModel



