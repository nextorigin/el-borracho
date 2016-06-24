express    = require "express"
override   = require "method-override"
errify     = require "errify"


class ElBorracho
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
    @router.del = @router.delete

  override: (req, res) ->
    return unless method = req.body?._method
    delete req.body._method
    method

  bindRoutes: ->
    state = ":state(active|completed|delayed|failed|wait|stuck)"
    @router.get  "/#{state}/:id/pending",          @makePendingById
    @router.get  "/#{state}/pending",              @makeAllPendingByState
    @router.get  "/#{state}",                      @allByState
    @router.del  "/#{state}",                      @deleteAllByState

    @router.get  "/:queue/#{state}/:id/pending",   @makePendingById
    @router.get  "/:queue/#{state}/pending",       @makePendingByState
    @router.get  "/:queue/#{state}/:id",           @dataById
    @router.get  "/:queue/#{state}",               @state
    @router.del  "/:queue/#{state}",               @deleteByState
    @router.del  "/:queue/:id",                    @deleteById
    @router.post "/:queue",                        @create
    @router.del  "/:queue",                        @deleteAll
    @router.get  "/",                              @queues

  makeAllPendingByState: (req, res, next) =>
    ideally = errify next
    {state} = req.params

    await @store.makePendingByState null, state, ideally defer results
    res.json message: results

  deleteAllByState: (req, res, next) =>
    ideally = errify next
    {state} = req.params

    await @store.deleteByState null, state, ideally defer results
    res.json message: results

  allByState: (req, res, next) =>
    ideally = errify next
    {state} = req.params

    await @store.jobs null, state, ideally defer results
    res.json results

  makePendingById: (req, res, next) =>
    ideally = errify next
    {id, queue, state} = req.params

    await @store.makePendingById queue, id, ideally defer results
    res.json message: results

  makePendingByState: (req, res, next) =>
    ideally = errify next
    {queue, state} = req.params

    await @store.makePendingByState queue, state, ideally defer results
    res.json message: results

  dataById: (req, res, next) =>
    ideally = errify next
    {id, queue, state} = req.params

    await @store.dataById queue, state, id, ideally defer results
    res.json message: results

  state: (req, res, next) =>
    ideally = errify next
    {queue, state} = req.params

    await @store.jobs queue, state, ideally defer jobs
    await @store.stateCounts        ideally defer counts
    res.json {jobs, counts}

  deleteByState: (req, res, next) =>
    ideally = errify next
    {queue, state} = req.params

    await @store.deleteByState queue, state, ideally defer results
    res.json message: results

  deleteById: (req, res, next) =>
    ideally = errify next
    {id, queue, state} = req.params

    await @store.deleteById queue, state, id, ideally defer results
    res.json message: results

  deleteAll: (req, res, next) =>
    ideally = errify next
    {queue} = req.params

    await @store.deleteAll queue, ideally defer results
    res.json message: results

  create: (req, res, next) =>
    return next new Error "job required" unless job = req.body
    ideally = errify next

    job = [job] unless Array.isArray job
    await @bull.createJobInQueue req.param.queue, job, ideally defer() for job in jobs

  queues: (req, res, next) =>
    ideally = errify next
    await @store.queues ideally defer results
    res.json results


module.exports = ElBorracho