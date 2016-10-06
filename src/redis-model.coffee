errify = require "errify"


queuenameMayHaveColon = (key) ->
  [_, queue..., id] = key.split ":"
  [(queue.join ":"), Number id]

flatten = (array) -> Array::concat array...


class RedisModel
  constructor: (@redis) ->

  jobs: (queue = "*", state, callback) ->
    ideally = errify callback

    await @idsAndCountByState queue, state,  ideally defer list
    await @fullKeysForList list,             ideally defer names
    await @formatJobs queue, names,          ideally defer jobs
    await @dataForJobs jobs,                 ideally defer jobs
    await @stacktraceForJobs jobs,           ideally defer jobs if state is "failed"
    await @progressForJobs jobs,             ideally defer jobs if state is "active"

    callback null, jobs

  jobsByQueue: (queue = "*", callback) ->
    ideally = errify callback

    await @allKeys queue,                    ideally defer names
    await @formatJobs queue, names,          ideally defer jobs
    await @dataForJobs jobs,                 ideally defer jobs
    await @stacktraceForJobs jobs,           ideally defer jobs
    await @progressForJobs jobs,             ideally defer jobs

    callback null, jobs

  idsAndCountByState: (queue = "*", state, callback) ->
    validStates = ["active", "completed", "delayed", "failed", "wait", "stuck"]
    return callback new Error "Invalid state: #{state} not in list of supported states" unless state in validStates
    return @idsAndCountByStuck queue, state, callback if state is "stuck"
    ideally = errify callback

    await @listsByState queue, state, ideally defer lists
    queues = []
    multi  = []
    ids    = {}
    count  = 0

    for list in lists when list = list.toString()
      [queuename, _] = queuenameMayHaveColon list
      queues.push queuename

      switch state
        when "active", "wait" then multi.push ["lrange",   list, 0, -1]
        when "delayed"        then multi.push ["zrange",   list, 0, -1]
        else                       multi.push ["smembers", list]

    return callback null, {ids, count} unless multi.length

    await (@redis.multi multi).exec ideally defer idsByList
    for idsOfList, i in idsByList
      NumberIdsOfList = (Number id for id in idsOfList)
      ids[queues[i]] = NumberIdsOfList
      count += idsOfList.length

    callback null, {ids, count}

  idsAndCountByStuck: (queue = "*", state, callback) ->
    ideally = errify callback

    await @stuckKeys queue, ideally defer keys
    response = ids: {}, count: keys.length

    for key in keys
      [queuename, id] = queuenameMayHaveColon key
      response.ids[queuename] or= []
      response.ids[queuename].push id

    callback null, response

  stuckKeys: (queue = "*", callback) ->
    ideally = errify callback

    validStates = ["active", "completed", "delayed", "failed", "wait"]

    lists = {}
    stuck = []
    for state in validStates
      await @idsAndCountByState queue, state, ideally defer list
      await @fullKeysForList list,            ideally defer keys
      lists[state] = keys

    await @allKeys queue, ideally defer allKeys

    for key in allKeys then do ->
      for state in validStates
        if key in (lists[state]? and lists[state]) then return
      stuck.push key

    callback null, stuck

  scanRedis: (match, callback) ->
    ideally = errify callback
    result  = []

    nextindex = 0
    while nextindex?
      await @redis.scan nextindex, "MATCH", match, ideally defer nextindexAndItems
      [nextindex, items] = nextindexAndItems
      result             = result.concat items
      nextindex          = parseInt nextindex
      if nextindex is 0 then nextindex = null

    callback null, result

  #Returns all JOB keys in string form (ex: bull:video transcoding:101)
  allKeys: (queue = "*", callback) ->
    ideally = errify callback

    await @scanRedis "bull:#{queue}:[0-9]*", ideally defer jobsWithLocks
    result = (jobWithLock for jobWithLock in jobsWithLocks when jobWithLock[-5..] isnt ":lock")
    callback null, result

  listsByState: (queue = "*", state, callback) ->
    await @scanRedis "bull:#{queue}:#{state}", callback

  #Returns the job data from a list of job ids
  fullKeysForList: (list, callback) ->
    return callback() unless list

    if queue = list.ids?["*"]
      @unknownKeysForIds queue, callback
    else if ids = list.ids
      fullKeys = ("bull:#{queuename}:#{id}" for id in queue for queuename, queue of ids)
      callback null, flatten fullKeys

  unknownKeysForIds: (ids, callback) ->
    return callback() unless ids and Array.isArray ids
    ideally = errify callback

    keys = []
    for id in ids
      await @scanRedis "bull:*:#{id}", ideally defer keymatches
      keys = keys.concat keymatches

    callback null, keys

  #Returns all jobs in object form, with state applied to object. Ex: {id: 101, queue: "video transcoding", state: "pending"}
  formatJobs: (queue = "*", keys, callback) ->
    return callback() unless keys
    ideally = errify callback

    states = ["active", "completed", "delayed", "failed", "wait", "stuck"]
    jobs   = []

    for state in states
      await @idsAndCountByState queue, state, ideally defer {ids}
      for key in keys
        [queuename, id] = queuenameMayHaveColon key
        if id in (ids[queuename]? and ids[queuename])
          jobs.push {queue: queuename, state, id}

    jobs = jobs.sort (a, b) ->
      aid = parseInt a.id
      bid = parseInt b.id
      if aid < bid then -1
      else if aid > bid then 1
      else 0

    callback null, jobs

  commandRemoveFromStateLists: (prefix, id) -> [
    ["lrem", "#{prefix}active",     0, id]
    ["lrem", "#{prefix}wait",       0, id]
    ["srem", "#{prefix}completed",  id]
    ["zrem", "#{prefix}delayed",    id]
    ["srem", "#{prefix}failed",     id]
  ]

  #Removes one or more jobs by ID, also removes the job from any state list it's in
  remove: (jobs, callback) ->
    return callback() unless jobs
    #Expects {id: 123, queue: "video transcoding"}
    multi = []
    for job in jobs
      {id, queue} = job
      prefix = "bull:#{queue}:"
      multi.push ["del", "#{prefix}#{id}"]
      multi = multi.concat @commandRemoveFromStateLists prefix, id

    (@redis.multi multi).exec callback

  #Makes all jobs in a specific state pending
  makePendingByState: (queue = "*", state, callback) ->
    validStates = ["active", "completed", "delayed", "failed", "wait"]
    #I could add stuck, but I won't support mass modifying "stuck" jobs because it's very possible for things to be in a "stuck" state temporarily, while transitioning between states

    return callback new Error "Invalid state: #{state} not in list of supported states" unless state in validStates
    ideally = errify callback

    await @idsAndCountByState queue, state, ideally defer {ids}
    multi = []
    for queuename, list of ids
      prefix = "bull:#{queuename}:"
      for id in list
        multi = multi.concat @commandRemoveFromStateLists prefix, id
        multi.push ["rpush", "#{prefix}wait", id]
        multi.push ["publish", "#{prefix}jobs", id]

    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully made all #{queue} jobs pending."

  #Makes a job with a specific ID pending, requires the queue of job as the first parameter and ID as second.
  makePendingById: (queue, id, callback) ->
    return callback "queue required" unless queue
    return callback "id required"    unless id
    ideally = errify callback

    prefix = "bull:#{queue}:"
    multi  = @commandRemoveFromStateLists prefix, id
    multi.push ["rpush", "#{prefix}wait", id]
    multi.push ["publish", "#{prefix}jobs", id]
    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully made #{queue} job ##{id} pending."

  deleteByState: (queue = "*", state, callback) ->
    validStates = ["active", "completed", "delayed", "failed", "wait"]
    #I could add stuck, but I won't support mass modifying "stuck" jobs because it's very possible for things to be in a "stuck" state temporarily, while transitioning between states

    return callback new Error "Invalid state: #{state} not in list of supported states" unless state in validStates
    ideally = errify callback

    await @idsAndCountByState queue, state, ideally defer {ids}
    multi = []
    for queuename, list of ids
      prefix = "bull:#{queuename}:"
      for id in list
        multi = multi.concat @commandRemoveFromStateLists prefix, id
        multi.push ["del", "#{prefix}#{id}"]

    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully deleted all #{state} jobs of queue #{queue}."

  deleteById: (queue, id, callback) ->
    return callback "queue required" unless queue
    return callback "id required"    unless id
    ideally = errify callback

    prefix = "bull:#{queue}:"
    multi  = @commandRemoveFromStateLists prefix, id
    multi.push ["del", "#{prefix}#{id}"]
    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully deleted job #{queue} ##{id}."

  deleteAll: (queue = "*", callback) ->
    ideally = errify callback

    prefix = "bull:#{queue}:*"
    multi  = [["eval", "for _,k in ipairs(redis.call('keys','#{prefix}')) do redis.call('del',k) end", 0]]
    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully deleted all jobs of queue #{queue}."

  dataById: (queue, id, callback) ->
    return callback "queue required" unless queue
    return callback "id required"    unless id
    ideally = errify callback

    key = "bull:#{queue}:#{id}"
    await @redis.exists key, ideally defer exists
    return callback null unless exists

    await @formatJobs queue, [key], ideally defer jobs
    [job] = jobs
    await @redis.hgetall key, ideally defer result
    for property, stringified of result when stringified.trim() isnt ""
      job[property] = JSON.parse stringified

    callback null, job

  dataForJobs: (jobs, callback) ->
    ideally = errify callback

    multi = for job in jobs
      ["hget", "bull:#{job.queue}:#{job.id}", "data"]

    await (@redis.multi multi).exec ideally defer results
    job.data = JSON.parse results[i] for job, i in jobs
    callback null, jobs

  progressForJobs: (jobs, callback) ->
    ideally = errify callback

    multi = for job in jobs
      ["hget", "bull:#{job.queue}:#{job.id}", "progress"]

    await (@redis.multi multi).exec ideally defer results
    job.progress = JSON.parse results[i] for job, i in jobs
    callback null, jobs

  stacktraceForJobs: (jobs, callback) ->
    ideally = errify callback

    multi = for job in jobs
      ["hget", "bull:#{job.queue}:#{job.id}", "stacktrace"]

    await (@redis.multi multi).exec ideally defer results
    job.stacktrace = JSON.parse results[i] for job, i in jobs
    callback null, jobs

  delayTimeForJobs: (jobs, callback) ->
    ideally = errify callback
    multi   = for job in jobs
      ["zscore", "bull:#{job.queue}:delayed", job.id]

    await (@redis.multi multi).exec ideally defer results
    for job, i in jobs
      # Bull packs delay expire timestamp and job id into a single number. This is mostly
      # needed to preserve execution order – first part of the resulting number contains
      # the timestamp and the end contains the incrementing job id. We don't care about
      # the id, so we can just remove this part from the value.
      # https://github.com/OptimalBits/bull/blob/e38b2d70de1892a2c7f45a1fed243e76fd91cfd2/lib/scripts.js#L90
      job.delayUntil = new Date Math.floor results[i]/0x1000

    callback null, jobs

  queues: (callback) ->
    ideally   = errify callback
    allCounts = []

    await @scanRedis "bull:*:id", ideally defer queues
    for queue, i in queues
      name = queue[5..-4]
      await @stateCounts name, ideally defer allCounts[i]

    callback null, allCounts

  stateCounts: (queue, callback) ->
    ideally = errify callback

    prefix = "bull:#{queue}"
    await @redis.lrange "#{prefix}:active", 0, -1, ideally defer activeIds
    active = []
    stuck  = []
    for id in activeIds
      await @redis.get "#{prefix}:#{id}:lock", ideally defer lock
      if lock? then active.push id
      else          stuck.push  id

    await @redis.scard "#{prefix}:completed", ideally defer completed
    await @redis.zcard "#{prefix}:delayed",   ideally defer delayed
    await @redis.llen  "#{prefix}:wait",      ideally defer wait
    await @redis.scard "#{prefix}:failed",    ideally defer failed

    callback null,
      name:      queue
      active:    active.length
      stuck:     stuck.length
      wait:      wait
      delayed:   delayed
      completed: completed
      failed:    failed


module.exports = RedisModel
