Queue = require "bull"
redis = require "redis"
log   = console.log.bind console


class JobCreator
  constructor: ->
    @proteins = "carnitas brisket camarones".split " "
    @salsas   = "habanero chipotle tomatillo".split " "
    @client   = redis.createClient()
    @queue    = Queue "tacos"

    @queue.process @cookTaco

  cookTaco: (job, done) ->
    {data} = job
    {protein, salsa, cooktime, orderNumber} = data
    log "##{orderNumber}: #{protein}, #{salsa} cooking for #{(cooktime/1000).toFixed 2}s"
    wake = ->
      log "##{orderNumber}: #{protein}, #{salsa} served"
      done()
    setTimeout wake, cooktime

  makeJob: (orderNumber) ->
    protein  = @proteins[Math.floor Math.random() * 3]
    salsa    = @salsas[Math.floor Math.random() * 3]
    cooktime = Math.random() * 10 * 1000

    log "ordering taco ##{orderNumber} #{protein}, #{salsa} with cooktime #{(cooktime/1000).toFixed 2}s"
    @queue.add {protein, salsa, cooktime, orderNumber}

  keepMaking10PacksOfTacos: (num = 1) ->
    @makeJob i for i in [num..num+10]
    setTimeout (=> @keepMaking10PacksOfTacos ++num), 15 * 1000


module.exports = JobCreator
