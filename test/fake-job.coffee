redis      = require "ioredis"
errify     = require "errify"
BullModel  = require "../src/bull-model"


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


module.exports = fakeJob
