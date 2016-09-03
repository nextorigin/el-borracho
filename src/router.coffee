override       = require "method-override"
ElBorracho     = require "./el-borracho"


class ElBorrachoRouter
  constructor: ({redis, @router}) ->
    @borracho = new ElBorracho {redis}
    @router or= new (require "express").Router

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
