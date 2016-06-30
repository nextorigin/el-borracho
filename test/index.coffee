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


queuename = "test"

## https://github.com/OptimalBits/bull/issues/83
qCleaner  = (queue) ->
  clean = queue.clean.bind queue, 0
  queue.pause()
       .then clean 'completed'
       .then clean 'active'
       .then clean 'delayed'
       .then clean 'failed'
       .then -> queue.empty()
       # .then -> queue.close()


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


fakeJob = (name, data, state = "wait", callback) ->
  ideally   = errify callback
  bullModel = new BullModel redis.createClient()

  await bullModel.createJobInQueue name, data, ideally defer job
  queue = bullModel.queues[name]

  if state is "active"
    await (queue.moveJob "wait", "active").asCallback ideally defer()
  else if state is "delayed"
    await (queue.moveJob "wait", "active").asCallback ideally defer()
    await (job.moveToDelayed Date.now() + 1000 * 10).asCallback ideally defer()
  else unless state is "wait"
    await (queue.moveJob "wait", "active").asCallback ideally defer()
    await (job._moveToSet state).asCallback ideally defer()

  callback null, {queue, job}


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
      expect(ids[queuename]).to.contain(job.jobId)
      expect(count).to.equal 1

      otherStates = validStates[0..]
      otherStates.splice (otherStates.indexOf state), 1
      for otherState in otherStates
        await instance.idsAndCountByState queuename, otherState, ideally defer {ids, count}
        expect(ids[queuename]).to.not.exist
        expect(count).to.equal 0

      qCleaner(queue).asCallback done


describe "RedisModel", ->
  queuename = "test"

  client   = null
  instance = null
  beforeEach ->
    client   = redis.createClient()
    instance = new RedisModel client

  afterEach ->
    client   = null
    instance = null

  describe "##constructor", ->
    it "should set redis on the model", ->
      expect(instance.redis).to.equal client

  describe "##jobs", ->

  describe "##idsAndCountByState", ->
    queue     = null
    job       = null

    it "should callback with error if state is not valid", (done) ->
      await instance.idsAndCountByState null, "badstate", defer err, _
      expect(err.toString()).to.contain "Invalid state"
      done()

    validStates = ["active", "completed", "delayed", "failed", "wait"] #, "stuck"]
    for state in validStates then do (state) ->
      it "should return all jobs of state #{state}", (done) ->
        ideally   = errify done
        data      = {name: "testjob"}
        await fakeJob queuename, data, state, ideally defer {queue, job}

        await instance.idsAndCountByState queuename, state, ideally defer {ids, count}
        expect(count).to.equal 1

        qCleaner(queue).asCallback done

  describe "##idsAndCountByStuck", ->

  describe "##stuckKeys", ->

  describe "##allKeys", ->
    it "should return all keys from all queues by default", (done) ->
      ideally   = errify done
      data      = {name: "testjob"}

      await fakeJob queuename, data, null, ideally defer {queue, job}
      await fakeJob "test2",   data, null, ideally defer queueAndJob2

      await instance.allKeys null, ideally defer keys
      expect(keys.length).to.equal 2

      qCleaner queue
        .then -> qCleaner queueAndJob2.queue
        .asCallback done

    it "should return all keys from a specific queue", (done) ->
      ideally   = errify done
      data      = {name: "testjob"}

      await fakeJob queuename, data, null, ideally defer {queue, job}

      await instance.allKeys queuename, ideally defer keys
      expect(keys.length).to.equal 1

      qCleaner(queue).asCallback done

  describe "##listsByState", ->
    queue  = null
    queue2 = null

    before (done) ->
      ideally   = errify done
      data      = {name: "testjob"}

      validStates = ["active", "completed", "delayed", "failed", "wait"]
      for state in validStates
        await fakeJob queuename, data, state, ideally defer queueAndJob
        await fakeJob "test2",   data, state, ideally defer queueAndJob2
        queue  = queueAndJob.queue
        queue2 = queueAndJob2.queue

      setTimeout done, 150 ## slight delay to ensure all lists have time for creation

    after (done) ->
      qCleaner queue
        .then -> qCleaner queue2
        .asCallback done

    for name in ["*", "test", "test2"] then do (name) ->

      validStates = ["active", "completed", "delayed", "failed", "wait"]
      for state in validStates then do (state) ->
        it "should return all lists in queue #{name} of state #{state}", (done) ->
          ideally = errify done
          await instance.listsByState name, state, ideally defer lists
          if name is "*"
            expect(lists.length).to.equal 2
          else
            expect(lists.length).to.equal 1

          done()

  describe "##fullKeysForList", ->
    it "should find queues for unknown ids", (done) ->
      ideally = errify done
      data    = {name: "testjob"}
      await fakeJob queuename, data, null, ideally defer {queue, job}
      list = ids: "*": [job.jobId]

      await instance.fullKeysForList list, ideally defer fullKeys
      [fullKey] = fullKeys
      expect(fullKey).to.equal "bull:#{queuename}:#{job.jobId}"

      qCleaner(queue).asCallback done

    it "should return the full keynames for ids", (done) ->
      ideally = errify done
      list    = ids: {}
      id      = 7
      list.ids[queuename] = [id]

      await instance.fullKeysForList list, ideally defer fullKeys
      [fullKey] = fullKeys
      expect(fullKey).to.equal "bull:#{queuename}:#{id}"

      done()

  describe "##remove", ->
    it "should remove jobs by id", (done) ->
      ideally = errify done
      data    = {name: "testjob"}
      await fakeJob queuename, data, null, ideally defer {queue, job}

      formattedJob =
        id: job.jobId
        queue: queuename
      await instance.remove [formattedJob], ideally defer()
      await instance.unknownKeysForIds [formattedJob.id], ideally defer keys
      expect(keys).to.be.empty

      done()
