express    = require "express"
override   = require "method-override"
errify     = require "errify"


class ExpressBull
  constructor: ({@router, @redisClient}) ->
    throw new Error "redisClient required" unless @redisClient

    Store     = require "./redis-model"
    Bull      = require "./bull-model"
    @store    = new Store @redisClient
    @bull     = new Bull @redisClient
    @router or= new express.Router

    @loadMiddleware()
    @bindRoutes()

  loadMiddleware: ->
    @router.use override @override

  override: (req, res) ->
    return unless method = req.body?._method
    # look in urlencoded POST bodies and delete it
    delete req.body._method
    method

  bindRoutes: ->
    state = ":state(active|complete|failed|wait|stuck)"
    @router.get  "/#{state}/:id/pending",        @makePendingById
    @router.get  "/#{state}/pending",            @makeAllPendingByState
    @router.get  "/#{state}",                    @allBystate
    @router.del  "/#{state}",                    @deleteAllByState

    @router.get  "/:queue/:state/:id/pending",   @makePendingById
    @router.get  "/:queue/:state/pending",       @makePendingByState
    @router.get  "/:queue/:state/:id",           @dataById
    @router.del  "/:queue/:state/:id",           @deleteById
    @router.get  "/:queue/:state",               @state
    @router.del  "/:queue/:state",               @deleteByState
    @router.post "/:queue",                      @create
    @router.get  "/",                            @queues

  makeAllPendingByState: (req, res, next) ->
    ideally = errify next
    {state} = req.params

    await @store.makePendingByState null, state, ideally defer results
    res.json message: results

  deleteAllByState: (req, res, next) ->
    ideally = errify next
    {state} = req.params

    await @store.deleteByState null, state, ideally defer results
    res.json message: results

  allByState: (req, res, next) ->
    ideally = errify next
    {state} = req.params

    await @jobs null, state, ideally defer results
    res.json results

  makePendingById: (req, res, next) ->
    ideally = errify next
    {id, queue, state} = req.params

    await @store.makePendingById queue, state, id, ideally defer results
    res.json message: results

  makePendingByState: (req, res, next) ->
    ideally = errify next
    {queue, state} = req.params

    await @store.makePendingByState queue, state, ideally defer results
    res.json message: results

  dataById: (req, res, next) ->
    ideally = errify next
    {id, queue, state} = req.params

    await @store.dataById queue, state, id, ideally defer results
    res.json message: results

  deleteById: (req, res, next) ->
    ideally = errify next
    {id, queue, state} = req.params

    await @store.deleteById queue, state, id, ideally defer results
    res.json message: results

  deleteByState: (req, res, next) ->
    ideally = errify next
    {queue, state} = req.params
    if ids = req.query?.ids

    await @store.deleteByState queue, state, ideally defer results
    res.json message: results

  state: (req, res, next) ->
    ideally = errify next
    {queue, state} = req.params

    await @jobs queue, state, ideally defer results
    res.json results

  jobs: (queue, state, callback) ->
    ideally = errify callback

    await @store.jobsByState queue, state, ideally defer list
    await @store.jobsInList list,          ideally defer jobs
    await @store.formatJobs jobs,          ideally defer jobs
    await @store.dataForJobs jobs,         ideally defer jobs
    await @store.stackTraceForJobs jobs,   ideally defer jobs
    await @store.progressForJobs jobs,     ideally defer jobs if state is "active"
    await @store.stateCounts               ideally defer counts

    callback null, {jobs, counts}

  create: (req, res, next) ->
    return next new Error "job required" unless job = req.body
    ideally = errify next

    job = [job] unless Array.isArray job
    await @bull.createJobInQueue req.param.queue, job, ideally defer() for job in jobs

  queues: (req, res, next) ->
    ideally = errify next
    await @store.queues ideally defer results
    res.json results


module.exports = ExpressBull
