SSEriesOfTubes = require "sseries-of-tubes"
override       = require "method-override"
ElBorracho     = require "./el-borracho"


class ElBorrachoRouter
  constructor: ({server, redis, @router}) ->
    @tubes    = new SSEriesOfTubes server
    @borracho = new ElBorracho {redis}
    @router or= new (require "express").Router
    @mount  or= "/jobs"

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

    @router.get  "/sse/multiplex",                 @tubes.multiplex @router
    @router.get  "/sse/#{state}",                  @tubes.plumb @borracho.allByState,    10,  "jobs"
    @router.get  "/sse/:queue/counts",             @tubes.plumb @borracho.counts,        10,  "counts"
    @router.get  "/sse/:queue/#{state}",           @tubes.plumb @borracho.state,         10,  "jobs"
    @router.get  "/sse/:queue/:id",                @tubes.plumb @borracho.dataById,      2,   "jobs"
    @router.get  "/sse/:queue",                    @tubes.plumb @borracho.all,           10,  "jobs"
    @router.get  "/sse",                           @tubes.plumb @borracho.queues,        10,  "counts"

    @router.get  "/#{state}/pending",              @borracho.makeAllPendingByState
    @router.get  "/#{state}",                      @borracho.allByState
    @router.del  "/#{state}",                      @borracho.deleteAllByState

    @router.get  "/:queue/counts",                 @borracho.counts
    @router.get  "/:queue/#{state}/pending",       @borracho.makePendingByState
    @router.get  "/:queue/#{state}",               @borracho.state
    @router.del  "/:queue/#{state}",               @borracho.deleteByState
    @router.get  "/:queue/:id/pending",            @borracho.makePendingById
    @router.get  "/:queue/:id",                    @borracho.dataById
    @router.del  "/:queue/:id",                    @borracho.deleteById
    @router.get  "/:queue",                        @borracho.all
    @router.post "/:queue",                        @borracho.create
    @router.del  "/:queue",                        @borracho.deleteAll
    @router.get  "/",                              @borracho.queues


module.exports = ElBorrachoRouter
