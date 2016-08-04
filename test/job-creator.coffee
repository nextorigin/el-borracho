Queue = require "bull"
redis = require "redis"
log   = console.log.bind console


class JobCreator
  constructor: (@queuename = "tacos") ->
    @proteins = "carnitas brisket camarones".split " "
    @salsas   = "habanero chipotle tomatillo".split " "
    @client   = redis.createClient()
    @queue    = Queue @queuename, createClient: => @client
    @queue1   = Queue @queuename, createClient: => @client
    @queue2   = Queue @queuename, createClient: => @client
    @queue3   = Queue @queuename, createClient: => @client
    @queue4   = Queue @queuename, createClient: => @client

    @queue.process  @cookTaco
    @queue1.process @cookTaco
    @queue2.process @cookTaco
    @queue3.process @cookTaco
    @queue4.process @cookTaco

  cookTaco: (job, done) ->
    {data, queue} = job
    {protein, salsa, cooktime, orderNumber} = data
    log "#{queue.name} ##{orderNumber}: #{protein}, #{salsa} cooking for #{(cooktime/1000).toFixed 2}s"
    wake = ->
      log "#{queue.name} ##{orderNumber}: #{protein}, #{salsa} served"
      done()
    setTimeout wake, cooktime

  makeJob: (orderNumber) ->
    protein  = @proteins[Math.floor Math.random() * 3]
    salsa    = @salsas[Math.floor Math.random() * 3]
    cooktime = Math.random() * 30 * 1000

    log "#{@queuename}: ordering ##{orderNumber} #{protein}, #{salsa} with cooktime #{(cooktime/1000).toFixed 2}s"
    @queue.add {protein, salsa, cooktime, orderNumber}

  keepMaking10PacksOfTacos: (num = 1) ->
    @makeJob i for i in [num..num+10]
    setTimeout (=> @keepMaking10PacksOfTacos ++num), 15 * 1000


module.exports = JobCreator
