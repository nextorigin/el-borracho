errify     = require "errify"


class ElBorracho
  constructor: ({@redis}) ->
    throw new Error "redis required" unless @redis

    Store     = require "./redis-model"
    Bull      = require "./bull-model"
    @store    = new Store @redis
    @bull     = new Bull @redis

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

    await @store.dataById queue, id, ideally defer results
    return next status: 404 unless results
    res.json results

  counts: (req, res, next) =>
    ideally = errify next
    {queue} = req.params

    await @store.stateCounts queue, ideally defer counts
    res.json counts

  state: (req, res, next) =>
    ideally = errify next
    {queue, state} = req.params

    await @store.jobs queue, state, ideally defer jobs
    res.json jobs

  deleteByState: (req, res, next) =>
    ideally = errify next
    {queue, state} = req.params

    await @store.deleteByState queue, state, ideally defer results
    res.json message: results

  deleteById: (req, res, next) =>
    ideally = errify next
    {id, queue, state} = req.params

    await @store.deleteById queue, id, ideally defer results
    res.json message: results

  deleteAll: (req, res, next) =>
    ideally = errify next
    {queue} = req.params

    await @store.deleteAll queue, ideally defer results
    res.json message: results

  all: (req, res, next) =>
    ideally = errify next
    {queue} = req.params

    await @store.jobsByQueue queue, ideally defer results
    res.json results

  create: (req, res, next) =>
    return next new Error "job required" unless job = req.body
    ideally = errify next

    jobs = [job] unless Array.isArray job
    await @bull.createJobInQueue req.param.queue, job, ideally defer() for job in jobs
    res.json message: "Sucessfully created jobs"

  queues: (req, res, next) =>
    ideally = errify next
    await @store.queues ideally defer results
    res.json results


module.exports = ElBorracho
