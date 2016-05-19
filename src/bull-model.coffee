Queue = require "bull"


class BullModel
  constructor: (@redisClient) ->
    @queues = {}

  client: => @redisClient

  createJobInQueue: (queue, job, callback) ->
    @queues[queue] or= new Queue queue, createClient: @client
    (@queues[queue].add job).asCallback callback


module.exports = BullModel
