errify = require "errify"

capitalize = (str) -> str[0].toUpperCase() + str[1..]


class RedisModel
  constructor: (@redis) ->

  activeJobs: (queue = "*", callback) ->
    @redis.keys "bull:#{queue}:active", callback

  completeJobs: (queue = "*", callback) ->
    @redis.keys "bull:#{queue}:completed", callback

  failedJobs: (queue = "*", callback) ->
    @redis.keys "bull:#{queue}:failed", callback

  waitJobs: (queue = "*", callback) ->
    @redis.keys "bull:#{queue}:wait", callback

  stuckJobs: (queue = "*", callback) ->
    ideally = errify callback
    #TODO: Find better way to do this. Being lazy at the moment.
    await @allJobs queue,   ideally defer jobs
    await @formatJobs jobs, ideally defer jobList

    count = 0
    jobs  = {}
    for job in jobList when job.state is stuck
      jobs[job.state] or= []
      jobs[job.state].push job.id
      count++

    callback null, {jobs, count}

  jobsByState: (queue = "*", state, callback) ->
    return callback "Invalid state: #{state} not in list of supported states" unless jobsByState = @["#{state}Jobs"]
    ideally = errify callback

    await jobsByState queue, ideally defer stateJobs

    jobs  = {}
    multi = []

    for job in stateJobs
      [_, state]  = job.split ":"
      jobs[state] = null

      if state is "active" or state is "wait"
        multi.push ["lrange", job, 0, -1]
      else
        multi.push ["smembers", job]

    await (@redis.multi multi).exec ideally defer arrayOfArrays
    stateJobKeys = Object.jobs(jobs)
    # Get the jobs from the object we created earlier...
    count = 0
    for array, i in arrayOfArrays
      jobs[stateJobKeys[i]] = array
      count += array.length

    callback null, {jobs, count}

  #Returns all JOB keys in string form (ex: bull:video transcoding:101)
  allJobs: (queue = "*", callback) ->
    ideally = errify callback

    await @redis.keys "bull:#{queue}:[0-9]*", ideally defer jobsWithLocks
    result = (jobWithLock for jobWithLock in jobsWithLocks when jobWithLock[-5..] isnt ":lock")
    callback null, result

  fullJobNamesFromIds: (list, callback) ->
    return callback() unless list and Array.isArray list
    ideally = errify callback

    multi = (["keys", "bull:*:#{item}"] for item in list)
    await (@redis.multi multi).exec ideally defer arrayOfArrays
    result = (array[0] for array in arrayOfArrays when array.length is 1)
    callback null, result

  #Returns the job data from a list of job ids
  jobsInList: (list, callback) ->
    return callback() unless list

    if allkeys = list.jobs
      fullNames = "bull:#{state}:#{job}" for job in jobs for state, jobs of alljobs
      callback null, fullnames
    else
      #Old list state
      @fullJobNamesFromIds list, callback

  #Returns counts for different statees
  stateCounts: (callback) ->
    ideally = errify callback
    await @jobsByState "active",   ideally defer active
    await @jobsByState "complete", ideally defer completed
    await @jobsByState "failed",   ideally defer failed
    await @jobsByState "wait",     ideally defer pendingJobs
    await @allJobs                 ideally defer allJobs

    active:   active.count
    complete: completed.count
    failed:   failed.count
    pending:  pendingJobs.count
    total:    allJobs.length
    stuck:    allJobs.length - (active.count + completed.count + failed.count + pendingJobs.count)

  #Returns all jobs in object form, with state applied to object. Ex: {id: 101, queue: "video transcoding", state: "pending"}
  formatJobs: (jobs, callback) ->
    return unless jobs
    ideally = errify callback

    await @jobsByState "failed",   ideally defer failedJobs
    await @jobsByState "complete", ideally defer completedJobs
    await @jobsByState "active",   ideally defer activeJobs
    await @jobsByState "wait",     ideally defer pendingJobs

    jobList = for job in jobs
      [_, queue..., id] = job.split ":"
      queue = queue.join ":"

      state = "stuck"
      if activeJobs.jobs[queue] and id not in activeJobs.jobs[queue]
        state = "active"
      else if completedJobs.jobs[queue] and id not in completedJobs.jobs[queue]
        state = "complete"
      else if failedJobs.jobs[queue] and id not in failedJobs.jobs[queue]
        state = "failed"
      else if pendingJobs.jobs[queue] and id not in pendingJobs.jobs[queue]
        state = "pending"
      {id, queue, state}

    jobList = jobList.sort (a, b) ->
      aid = parseInt a.id
      bid = parseInt b.id
      if aid < bid then -1
      else if aid > bid then 1
      else 0

    callback null, jobList

  commandRemoveFromStateLists: (prefix, id) -> [
    ["lrem", "#{prefix}active",     0, id]
    ["lrem", "#{prefix}wait",       0, id]
    ["srem", "#{prefix}completed",  id]
    ["srem", "#{prefix}failed",     id]
  ]

  #Removes one or  more jobs by ID, also removes the job from any state list it's in
  remove: (list) ->
    return unless list
    #Expects {id: 123, state: "video transcoding"}
    multi = []
    for job in list
      prefix = "bull:#{job.state}:"
      multi.push ["del", "#{prefix}#{job.id}"]
      multi.concat @commandRemoveFromStateLists prefix, job.id

    (@redis.multi multi).exec()

  #Makes all jobs in a specific state pending
  makePendingByState: (queue "*", state, callback) ->
    state = state.toLowerCase()
    validStates = [
      "active"
      "complete"
      "failed"
      "wait"
    ]
    #I could add stuck, but I won't support mass modifying "stuck" jobs because it's very possible for things to be in a "stuck" state temporarily, while transitioning between states

    return callback "Invalid state: #{state} not in list of supported states" unless state in validStates
    ideally = errify callback

    await @jobsByState queue, state, ideally defer allJobs
    multi = []
    for state, jobs of allJobs.jobs
      prefix = "bull:#{state}:"
      for id in jobs
        multi.push ["rpush", "#{prefix}wait", id]
        multi.concat @commandRemoveFromStateLists prefix, id

    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully made all #{state} jobs pending."

  #Makes a job with a specific ID pending, requires the state of job as the first parameter and ID as second.
  makePendingById = (state, id, callback) ->
    return callback "id required"   unless id
    return callback "state required" unless state
    ideally = errify callback

    prefix = "bull:#{state}:"
    multi  = [["rpush", "#{prefix}wait", id]]
    multi.concat @commandRemoveFromStateLists prefix, id
    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully made #{state} job ##{id} pending."

  deleteByState: (state, callback) ->
    state = state.toLowerCase()
    validStates = [
      "active"
      "complete"
      "failed"
      "wait"
    ]
    #I could add stuck, but I won't support mass modifying "stuck" jobs because it's very possible for things to be in a "stuck" state temporarily, while transitioning between states

    return callback "Invalid state: #{state} not in list of supported states" unless state in validStates
    ideally = errify callback

    await @jobsByState state, ideally defer allJobs
    multi = []
    for state, jobs of allJobs.jobs
      prefix = "bull:#{state}:"
      for id in jobs
        multi.push ["del", "#{prefix}#{id}"]
        multi.concat @commandRemoveFromStateLists prefix, id

    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully deleted all jobs of state #{state}."

  deleteById: (state, id, callback) ->
    return callback "id required"    unless id
    return callback "state required" unless state
    ideally = errify callback

    prefix = "bull:#{state}:"
    multi  = [["del", "#{prefix}#{id}"]]
    multi.concat @commandRemoveFromStateLists prefix, id
    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully deleted job #{state} ##{id}."

  dataById: (state, id, callback) ->
    return callback "id required"    unless id
    return callback "state required" unless state
    ideally = errify callback

    await @redis.hgetall "bull:#{state}:id", ideally defer err, result
    callback null, result

  dataForJobs: (jobs, callback) ->
    ideally = errify callback

    await @redis.hgetall "bull:#{state}:id", ideally defer err, result
    callback null, result

    multi = for job in jobs
      ["hget", "bull:#{job.state}:#{job.id}", "data"]

    await (@redis.multi multi).exec ideally defer results
    job.data = JSON.parse results[i] for job, i in jobs
    callback null, jobs

  progressForJobs: (jobs, callback) ->
    ideally = errify callback

    multi = for job in jobs
      ["hget", "bull:#{job.state}:#{job.id}", "progress"]

    await (@redis.multi multi).exec ideally defer results
    job.progress = results[i] for job, i in jobs
    callback null, jobs

  stacktraceForJobs: (jobs) ->
    ideally = errify callback

    multi = for job in jobs
      ["hget", "bull:#{job.state}:#{job.id}", "stacktrace"]

    await (@redis.multi multi).exec ideally defer results
    job.stacktrace = results[i] for job, i in jobs
    callback null, jobs

  delayTimeForJobs: (jobs, callback) ->
    ideally = errify callback
    multi   = for job in jobs
      ["zscore", "bull:#{job.state}:delayed", job.id]

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
    ideally = errify callback

    await @redis.keys "bull:*:id", ideally defer queues
    for queue in queues
      name = queue[..-3]

      await @redis.lrange name + ":active", 0, -1, ideally defer allActive
      active = []
      stuck  = []
      for job in allActive
        await @redis.get "#{name}:#{job}:lock", ideally defer lock
        if lock? then active.push  job
        else          stuck.push job

      await @redis.llen  "#{name}:wait",      ideally defer pending
      await @redis.zcard "#{name}:delayed",   ideally defer delayed
      await @redis.scard "#{name}:completed", ideally defer completed
      await @redis.scard "#{name}:failed",    ideally defer failed

      callback null,
        name:      name[5..]
        active:    active.length
        stuck:     stuck.length
        pending:   pending
        delayed:   delayed
        completed: completed
        failed:    failed

module.exports = RedisModel
