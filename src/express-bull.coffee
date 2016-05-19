express    = require "express"
errify     = require "errify"


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

  queues: (req, res, next) ->
    ideally = errify next
    await @Store.queues ideally defer results
    res.json results

  makePendingById: (req, res, next) ->
    ideally = errify next
    {id, state} = req.params

    await @Store.makePendingById state, id, ideally defer results
    res.json message: results

  deleteById: (req, res, next) ->
    ideally = errify next
    {id, state} = req.params

    await @Store.deleteById state, id, ideally defer results
    res.json message: results

  deleteByState: (req, res, next) ->
    ideally = errify next
    {state} = req.params

    await @Store.deleteByState state, ideally defer results
    res.json message: results

  dataById: (req, res, next) ->
    ideally = errify next
    {id, state} = req.params

    await @Store.dataById state, id, ideally defer results
    res.json message: results

  state: (req, res, next) ->
    ideally = errify next
    {state} = req.params

    await @jobs state, ideally defer results
    res.json results

  jobs: (state, callback) ->
    ideally = errify callback
    await @Store.jobsByState state, ideally defer list
    await @Store.jobsInList list,  ideally defer jobs
    await @Store.formatJobs jobs,  ideally defer jobs

    if state is "active"
      await @Store.getProgressForJobs jobs, ideally defer jobs

    await @Store.getStatusCounts ideally defer counts
    callback null, {jobs, counts}


module.exports = ExpressBull
