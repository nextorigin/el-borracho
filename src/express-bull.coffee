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
    @router.get "/queues",             @queues
    @router.get "/:state/:id/pending", @makePendingById
    @router.get "/:state/:id/delete",  @deleteById
    @router.get "/:state/delete",      @deleteByState
    @router.del "/:state/:id",         @deleteById
    @router.get "/:state/:id",         @dataById
    @router.get "/:state",             @state
    @router.del "/:state",             @deleteByState

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
