express    = require "express"
errify     = require "errify"
GetJobs    = require "./get_jobs"


class ExpressBull
  states: [
    "active"
    "wait"
    "failed"
    "complete"
  ]

  constructor: ({@router, @redisClient}) ->
    @router or= new express.Router
    throw new Error "redisClient required" unless @redisClient

    @Store = require "./redis-model"
    @Store.setup @redisClient

    @getJobs = GetJobs @Store
    bindRoutes()

  bindRoutes: ->
    @router.get "/#{state}", @getHandler state for state in @states
    @router.get "/data/id/:type/:id",    @dataById
    @router.get "/pending/id/:type/:id", @makePendingById
    @router.get "/delete/id/:type/:id",  @deleteById
    @router.get "/delete/status/:type",  @deleteByStatus
    @router.get "/queues",               @queues

  getHandler: (state) -> (req, res, next) ->
    ideally = errify next
    await @getJobs state, ideally defer results
    res.json results

  getJobs: (state) ->
    await @Store.statusKeys state, ideally defer list
    await @Store.jobsInList list,  ideally defer keys
    await @Store.formatKeys keys,  ideally defer keys

    if state is "active"
      await @Store.getProgressForKeys keys, ideally defer keys

    await @Store.getStatusCounts ideally defer counts
    callback null, {keys, counts}

  dataById: (req, res, next) ->
    ideally = errify next
    {id, type} = req.params

    await @Store.dataById type, id, ideally defer results
    res.json message: results

  makePendingById: (req, res, next) ->
    ideally = errify next
    {id, type} = req.params

    await @Store.makePendingById type, id, ideally defer results
    res.json message: results

  deleteById: (req, res, next) ->
    ideally = errify next
    {id, type} = req.params

    await @Store.deleteById type, id, ideally defer results
    res.json message: results

  deleteByStatus: (req, res, next) ->
    ideally = errify next
    {type} = req.params

    await @Store.deleteByStatus type, ideally defer results
    res.json message: results

  queues: (req, res, next) ->
    ideally = errify next
    await @Store.queues ideally defer results
    res.json results


module.exports = ExpressBull
