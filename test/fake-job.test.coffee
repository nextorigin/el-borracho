redis      = require "ioredis"
{expect}   = require "chai"
errify     = require "errify"
RedisModel = require "../src/redis-model"
qCleaner   = require "./q-cleaner"
fakeJob    = require "./fake-job"


describe "fakeJob", ->
  queuename = "test"

  client   = null
  instance = null
  beforeEach ->
    client   = redis.createClient()
    instance = new RedisModel client

  afterEach ->
    client   = null
    instance = null

  validStates = ["active", "completed", "delayed", "failed", "wait"] #, "stuck"]
  for state in validStates then do (state) ->
    it "should create a fake job in state #{state} and add it to the correct state list", (done) ->
      ideally = errify done
      data    = {name: "testjob"}
      queue   = null
      await fakeJob queuename, data, state, ideally defer {queue, job}

      await instance.idsAndCountByState queuename, state, ideally defer {ids, count}
      expect(ids[queuename]).to.contain job.jobId
      expect(count).to.equal 1

      otherStates = validStates[0..]
      otherStates.splice (otherStates.indexOf state), 1
      for otherState in otherStates
        await instance.idsAndCountByState queuename, otherState, ideally defer {ids, count}
        expect(ids[queuename]).to.not.exist
        expect(count).to.equal 0

      qCleaner(queue).asCallback done

