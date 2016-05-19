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
    throw new Error "redisClient required" unless @redisClient

    Store     = require "./redis-model"
    Bull      = require "./bull-model"
    @store    = new Store @redisClient
    @bull     = new Bull @redisClient
    @router or= new express.Router

    bindRoutes()

  bindRoutes: ->
    @router.get  "/queues",             @queues
    @router.get  "/:state/:id/pending", @makePendingById
    @router.get  "/:state/:id/delete",  @deleteById
    @router.get  "/:state/delete",      @deleteByState
    @router.del  "/:state/:id",         @deleteById
    @router.get  "/:state/:id",         @dataById
    @router.get  "/:state",             @state
    @router.del  "/:state",             @deleteByState
    @router.post "/",                   @create

  queues: (req, res, next) ->
    ideally = errify next
    await @store.queues ideally defer results
    res.json results

  makePendingById: (req, res, next) ->
    ideally = errify next
    {id, state} = req.params

    await @store.makePendingById state, id, ideally defer results
    res.json message: results

  deleteById: (req, res, next) ->
    ideally = errify next
    {id, state} = req.params

    await @store.deleteById state, id, ideally defer results
    res.json message: results

  deleteByState: (req, res, next) ->
    ideally = errify next
    {state} = req.params

    await @store.deleteByState state, ideally defer results
    res.json message: results

  dataById: (req, res, next) ->
    ideally = errify next
    {id, state} = req.params

    await @store.dataById state, id, ideally defer results
    res.json message: results

  state: (req, res, next) ->
    ideally = errify next
    {state} = req.params

    await @jobs state, ideally defer results
    res.json results

  jobs: (state, callback) ->
    ideally = errify callback

    await @store.jobsByState state,         ideally defer list
    await @store.jobsInList list,           ideally defer jobs
    await @store.formatJobs jobs,           ideally defer jobs
    await @store.getDataForJobs jobs,       ideally defer jobs
    await @store.getStackTraceForJobs jobs, ideally defer jobs
    await @store.getProgressForJobs jobs,   ideally defer jobs if state is "active"
    await @store.getStatusCounts            ideally defer counts

    callback null, {jobs, counts}

  create: (req, res, next) ->
    return next new Error "job required" unless job = req.body
    ideally = errify next

    job = [job] unless Array.isArray job
    await @bull.createJobInQueue req.param.queue, job, ideally defer() for job in jobs


module.exports = ExpressBull
