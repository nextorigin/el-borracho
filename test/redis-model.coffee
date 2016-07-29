redis      = require "redis"
{expect}   = require "chai"
errify     = require "errify"
RedisModel = require "../src/redis-model"
qCleaner   = require "./q-cleaner"
fakeJob    = require "./fake-job"


queuename = "test"


describe "RedisModel", ->

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
    it "should return from all queues all jobs of a specific state", (done) ->
      ideally = errify done
      data    = {name: "testjob", foo: "bar"}
      state   = "active"

      await fakeJob queuename, data, state, ideally defer {queue, job}
      await fakeJob "test2",   data, state, ideally defer queueAndJob2

      await instance.jobs null, state, ideally defer jobs
      jobInterface =
        id:         0
        progress:   0
        queue:      "name"
        # stacktrace: []

      expect(jobs.length).to.equal 2
      for jobWithData in jobs
        expect(jobWithData.state).to.equal state
        expect(jobWithData.data).to.deep.equal data
        expect(jobWithData.stacktrace).to.be.an "array"
        for property, value of jobInterface
          expect(jobWithData[property]).to.be.a typeof value

      qCleaner queue
        .then -> qCleaner queueAndJob2.queue
        .asCallback done

    it "should return from a specific queue all jobs of a specific state", (done) ->
      ideally = errify done
      data    = {name: "testjob", foo: "bar"}
      state   = "active"

      await fakeJob queuename, data, state, ideally defer {queue, job}
      await fakeJob queuename, data, state, ideally defer queueAndJob2

      await instance.jobs queuename, state, ideally defer jobs
      jobInterface =
        id:         0
        progress:   0
        queue:      "name"
        # stacktrace: []

      expect(jobs.length).to.equal 2
      for jobWithData in jobs
        expect(jobWithData.queue).to.equal queuename
        expect(jobWithData.state).to.equal state
        expect(jobWithData.data).to.deep.equal data
        expect(jobWithData.stacktrace).to.be.an "array"
        for property, value of jobInterface
          expect(jobWithData[property]).to.be.a typeof value

      qCleaner(queue).asCallback done

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
        expect(ids[queuename]).to.contain(job.jobId)
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

    afterEach (done) ->
      ideally = errify done
      await instance.allKeys null, ideally defer keys
      for key in keys
        await instance.deleteById queuename, (key.split ":")[-1..][0], ideally defer _
      done()

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
    it "should return early and empty if not provided keys", (done) ->
      ideally = errify done

      await instance.fullKeysForList null, ideally defer fullKeys
      expect(fullKeys).to.be.empty

      done()

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

  describe "##unknownKeysForIds", ->
    it "should return early and empty if not provided ids", (done) ->
      ideally = errify done

      await instance.unknownKeysForIds null, ideally defer fullKeys
      expect(fullKeys).to.be.empty

      done()

  describe "##formatJobs", ->
    queues   = []
    jobIds   = []

    before (done) ->
      ideally   = errify done
      data      = {name: "testjob"}

      validStates = ["active", "completed", "delayed", "failed", "wait"]
      for state in validStates
        await fakeJob queuename, data, state, ideally defer {queue, job}
        queues = [queue]
        jobIds.push job.jobId

      done()

    afterEach (done) ->
      ideally = errify done
      await instance.allKeys null, ideally defer keys
      for key in keys
        await instance.deleteById queuename, (key.split ":")[-1..][0], ideally defer _
      done()

    after (done) ->
      ideally = errify done

      for queue in queues
        await qCleaner(queue).asCallback ideally defer _
      queues  = []
      jobIds  = []

      done()

    it "should return early and empty if not provided keys", (done) ->
      ideally = errify done

      await instance.formatJobs null, null, ideally defer jobs
      expect(jobs).to.be.empty

      done()

    it "should return jobs formatted with state, sorted by id", (done) ->
      ideally = errify done
      list    = ids: {}
      list.ids[queuename] = jobIds
      await instance.fullKeysForList list, ideally defer keys

      await instance.formatJobs queuename, keys, ideally defer jobs
      lastId = 0
      expect(jobs.length).to.equal 5
      for job in jobs
        expect(job.state).to.exist
        id = Number job.id
        expect(id).to.be.above lastId
        lastId = id

      done()

  describe "##remove", ->
    it "should return early and empty if not provided jobs", (done) ->
      ideally = errify done

      await instance.remove null, ideally defer result
      expect(result).to.be.empty

      done()

    it "should remove jobs by id", (done) ->
      ideally = errify done
      data    = {name: "testjob"}
      await fakeJob queuename, data, null, ideally defer {queue, job}
      await fakeJob queuename, data, null, ideally defer queueAndJob2

      formattedJobs = [
        {id: job.jobId,              queue: queuename}
        {id: queueAndJob2.job.jobId, queue: queuename}
      ]
      ids = (job.id for job in formattedJobs)
      await instance.remove formattedJobs, ideally defer()
      await instance.unknownKeysForIds ids, ideally defer keys
      expect(keys).to.be.empty

      done()

  describe "##makePendingByState", ->
    it "should callback with error if state is not valid", (done) ->
      await instance.makePendingByState null, "badstate", defer err, _
      expect(err.toString()).to.contain "Invalid state"
      done()

    it "should make pending in all queues all jobs of a specific state", (done) ->
      ideally = errify done
      data    = {name: "testjob"}

      await fakeJob queuename, data, "active", ideally defer {queue, job}
      await fakeJob "test2", data, "active", ideally defer queueAndJob2

      await instance.makePendingByState null, "active", ideally defer _
      await instance.idsAndCountByState null, "wait", ideally defer {ids, count}
      expect(ids[queuename]).to.contain job.jobId
      expect(ids["test2"]).to.contain queueAndJob2.job.jobId
      expect(count).to.equal 2

      qCleaner queue
        .then -> qCleaner queueAndJob2.queue
        .asCallback done

    it "should make pending in a specific queue all jobs of a specific state", (done) ->
      ideally = errify done
      data    = {name: "testjob"}

      await fakeJob queuename, data, "active", ideally defer {queue, job}
      await instance.makePendingByState queuename, "active", ideally defer _
      await instance.idsAndCountByState queuename, "wait", ideally defer {ids, count}
      expect(ids[queuename]).to.contain job.jobId
      expect(count).to.equal 1

      qCleaner(queue).asCallback done

  describe "##makePendingById", ->
    it "should callback with error if missing queue parameter", (done) ->
      await instance.makePendingById null, 1, defer err, _
      expect(err.toString()).to.contain "queue required"
      done()

    it "should callback with error if missing id parameter", (done) ->
      await instance.makePendingById "queuename", null, defer err, _
      expect(err.toString()).to.contain "id required"
      done()

    it "should make pending in a specific queue a job by id", (done) ->
      ideally = errify done
      data    = {name: "testjob"}

      await fakeJob queuename, data, "active", ideally defer {queue, job}
      await instance.makePendingById queuename, job.jobId, ideally defer _
      await instance.idsAndCountByState queuename, "wait", ideally defer {ids, count}
      expect(ids[queuename]).to.contain job.jobId
      expect(count).to.equal 1

      qCleaner(queue).asCallback done

  describe "##deleteByState", ->
    it "should callback with error if state is not valid", (done) ->
      await instance.deleteByState null, "badstate", defer err, _
      expect(err.toString()).to.contain "Invalid state"
      done()

    it "should delete in all queues all jobs of a specific state", (done) ->
      ideally = errify done
      data    = {name: "testjob"}

      await fakeJob queuename, data, "active", ideally defer {queue, job}
      await fakeJob "test2", data, "active", ideally defer queueAndJob2

      await instance.deleteByState null, "active", ideally defer _
      await instance.allKeys null, ideally defer keys
      expect(keys).to.be.empty
      done()

    it "should delete in a specific queue all jobs of a specific state", (done) ->
      ideally = errify done
      data    = {name: "testjob"}

      await fakeJob queuename, data, "active", ideally defer {queue, job}
      await instance.deleteByState queuename, "active", ideally defer _
      await instance.allKeys null, ideally defer keys
      expect(keys).to.be.empty
      done()

  describe "##deleteById", ->
    it "should callback with error if missing queue parameter", (done) ->
      await instance.deleteById null, 1, defer err, _
      expect(err.toString()).to.contain "queue required"
      done()

    it "should callback with error if missing id parameter", (done) ->
      await instance.deleteById "queuename", null, defer err, _
      expect(err.toString()).to.contain "id required"
      done()

    it "should delete in a specific queue a job by id", (done) ->
      ideally = errify done
      data    = {name: "testjob"}

      await fakeJob queuename, data, "active", ideally defer {queue, job}
      await instance.deleteById queuename, job.jobId, ideally defer _
      await instance.dataById queuename, job.jobId, ideally defer data
      expect(data).to.be.empty
      done()

  describe "##deleteAll", ->
    it "should delete in all queues all jobs", (done) ->
      ideally = errify done
      data    = {name: "testjob"}

      await fakeJob queuename, data, "active", ideally defer {queue, job}
      await instance.deleteAll null, ideally defer _
      await instance.allKeys null, ideally defer keys
      expect(keys).to.be.empty
      done()

    it "should delete in a specific queue all jobs", (done) ->
      ideally = errify done
      data    = {name: "testjob"}

      await fakeJob queuename, data, "active", ideally defer {queue, job}
      await instance.deleteAll queuename, ideally defer _
      await instance.allKeys null, ideally defer keys
      expect(keys).to.be.empty
      done()

  describe "##dataById", ->
    it "should callback with error if missing queue parameter", (done) ->
      await instance.dataById null, 1, defer err, _
      expect(err.toString()).to.contain "queue required"
      done()

    it "should callback with error if missing id parameter", (done) ->
      await instance.dataById "queuename", null, defer err, _
      expect(err.toString()).to.contain "id required"
      done()

    it "should get from a specific queue data for a job by id", (done) ->
      ideally = errify done
      data    = {name: "testjob", foo: "bar"}

      await fakeJob queuename, data, "active", ideally defer {queue, job}

      await instance.dataById queuename, job.jobId, ideally defer allJobData
      allJobDataInterface =
        attempts:     1
        attemptsMade: 0
        # data:         {}
        delay:         0
        opts:         {}
        progress:     0
        # returnvalue:  null
        stacktrace:   []
        timestamp:    1467326353545

      for own property, value of allJobDataInterface
        type = if Array.isArray value then "array" else typeof value
        expect(allJobData[property]).to.be.a type
      expect(allJobData.data).to.deep.equal data

      qCleaner(queue).asCallback done

  describe "##dataForJobs", ->
    it "should get data for jobs", (done) ->
      ideally = errify done
      data    = {name: "testjob", foo: "bar"}

      await fakeJob queuename, data, "active",  ideally defer {queue, job}
      await fakeJob "test2",   data, "delayed", ideally defer queueAndJob2

      jobs = [
        {queue: job.queue.name,          id: job.jobId}
        {queue: queueAndJob2.queue.name, id: queueAndJob2.job.jobId}
      ]
      await instance.dataForJobs jobs, ideally defer jobsWithData
      for jobWithData in jobsWithData
        expect(jobWithData.data).to.deep.equal data

      qCleaner queue
        .then -> qCleaner queueAndJob2.queue
        .asCallback done

  describe "##progressForJobs", ->
    it "should get stacktrace for jobs", (done) ->
      ideally = errify done
      data    = {name: "testjob", foo: "bar"}

      await fakeJob queuename, data, "active",  ideally defer {queue, job}
      await fakeJob "test2",   data, "delayed", ideally defer queueAndJob2

      jobs = [
        {queue: job.queue.name,          id: job.jobId}
        {queue: queueAndJob2.queue.name, id: queueAndJob2.job.jobId}
      ]
      await instance.progressForJobs jobs, ideally defer jobsWithProgress
      for jobWithProgress in jobsWithProgress
        expect(jobWithProgress.progress).to.equal 0

      qCleaner queue
        .then -> qCleaner queueAndJob2.queue
        .asCallback done

  describe "##stacktraceForJobs", ->
    it "should get stacktrace for jobs", (done) ->
      ideally = errify done
      data    = {name: "testjob", foo: "bar"}

      await fakeJob queuename, data, "active",  ideally defer {queue, job}
      await fakeJob "test2",   data, "delayed", ideally defer queueAndJob2

      jobs = [
        {queue: job.queue.name,          id: job.jobId}
        {queue: queueAndJob2.queue.name, id: queueAndJob2.job.jobId}
      ]
      await instance.stacktraceForJobs jobs, ideally defer jobsWithStacktrace
      for jobWithStacktrace in jobsWithStacktrace
        expect(jobWithStacktrace.stacktrace).to.be.an "array"

      qCleaner queue
        .then -> qCleaner queueAndJob2.queue
        .asCallback done

  describe "##delayTimeForJobs", ->
    it "should get delay time for jobs", (done) ->
      ideally = errify done
      data    = {name: "testjob", foo: "bar"}

      await fakeJob queuename, data, "active",  ideally defer {queue, job}
      await fakeJob "test2",   data, "delayed", ideally defer queueAndJob2

      jobs = [
        {queue: job.queue.name,          id: job.jobId}
        {queue: queueAndJob2.queue.name, id: queueAndJob2.job.jobId}
      ]
      await instance.delayTimeForJobs jobs, ideally defer jobsWithDelay
      for jobWithDelay in jobsWithDelay
        expect(jobWithDelay.delayUntil).to.be.an.instanceof Date

      qCleaner queue
        .then -> qCleaner queueAndJob2.queue
        .asCallback done

  describe "##queues", ->
    it "should get all queues with counts", (done) ->
      ideally = errify done
      data    = {name: "testjob", foo: "bar"}

      await fakeJob queuename, data, "active",  ideally defer {queue, job}
      await fakeJob "test2",   data, "delayed", ideally defer queueAndJob2

      await instance.queues ideally defer queues
      expected =
        test:
          active:    0
          completed: 0
          delayed:   0
          failed:    0
          name:      "test"
          stuck:     1
          wait:      0
        test2:
          active:    0
          completed: 0
          delayed:   1
          failed:    0
          name:      "test2"
          stuck:     0
          wait:      0

      expect(queues).to.deep.equal expected

      qCleaner queue
        .then -> qCleaner queueAndJob2.queue
        .asCallback done

  describe "##stateCounts", ->
