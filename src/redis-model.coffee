errify = require "errify"

capitalize = (str) -> str[0].toUpperCase() + str[1..]


class RedisModel
  constructor: (@redis) ->

  activeKeys: (queue = "*", callback) ->
    @redis.keys "bull:#{queue}:active", callback

  completeKeys: (queue = "*", callback) ->
    @redis.keys "bull:#{queue}:completed", callback

  failedKeys: (queue = "*", callback) ->
    @redis.keys "bull:#{queue}:failed", callback

  waitKeys: (queue = "*", callback) ->
    @redis.keys "bull:#{queue}:wait", callback

  stuckKeys: (queue = "*", callback) ->
    ideally = errify callback
    #TODO: Find better way to do this. Being lazy at the moment.
    await @allKeys queue, ideally defer keys
    await @formatKeys keys, ideally defer keyList

    count = 0
    keys  = {}
    for key in keyList when key.status is stuck
      keys[key.type] or= []
      keys[key.type].push key.id
      count++

    callback null, {keys, count}

  #Returns indexes of completed jobs
  statusKeys: (status, callback) ->
    ideally = errify callback

    await @["#{status}Keys"] ideally defer statusKeys

    keys  = {}
    multi = []

    for key in statusKeys
      [_, type]  = key.split ":"
      keys[type] = null

      if status is "active" or status is "wait"
        multi.push ["lrange", key, 0, -1]
      else
        multi.push ["smembers", key]

    await (@redis.multi multi).exec ideally defer arrayOfArrays
    statusKeyKeys = Object.keys(keys)
    # Get the keys from the object we created earlier...
    count = 0
    for array, i in arrayOfArrays
      keys[statusKeyKeys[i]] = array
      count += array.length

    callback null, {keys, count}

  #Returns all JOB keys in string form (ex: bull:video transcoding:101)
  allKeys: (queue = "*", callback) ->
    ideally = errify callback

    await @redis.keys "bull:#{queue}:[0-9]*" ideally defer keysWithLocks
    result = (keyWithLock for keyWithLock in keysWithLocks when keyWithLock[-5..] isnt ":lock")
    callback null, result

  fullKeyNamesFromIds: (list, callback) ->
    return callback() unless list and Array.isArray list
    ideally = errify callback

    multi = (["keys", "bull:*:#{item}"] for item in list)
    await (@redis.multi multi).exec ideally defer arrayOfArrays
    result = (array[0] for array in arrayOfArrays when array.length is 1)
    callback null, result

  #Returns the job data from a list of job ids
  jobsInList: (list, callback) ->
    return callback() unless list

    if allkeys = list.keys
      fullNames = "bull:#{type}:#{key}" for key in keys for type, keys of allkeys
      callback null, fullnames
    else
      #Old list type
      @fullKeyNamesFromIds list, callback

  #Returns counts for different statuses
  statusCounts: (callback) ->
    ideally = errify callback
    await @statusKeys "active",   ideally defer active
    await @statusKeys "complete", ideally defer completed
    await @statusKeys "failed",   ideally defer failed
    await @statusKeys "wait",     ideally defer pendingKeys
    await @allKeys                ideally defer allKeys

    active:   active.count
    complete: completed.count
    failed:   failed.count
    pending:  pendingKeys.count
    total:    allKeys.length
    stuck:    allKeys.length - (active.count + completed.count + failed.count + pendingKeys.count)

  #Returns all keys in object form, with status applied to object. Ex: {id: 101, type: "video transcoding", status: "pending"}
  formatKeys: (keys, callback) ->
    return unless keys
    ideally = errify callback

    await @statusKeys "failed",   ideally defer failedJobs
    await @statusKeys "complete", ideally defer completedJobs
    await @statusKeys "active",   ideally defer activeJobs
    await @statusKeys "wait",     ideally defer pendingJobs

    keyList = for key in keys
      [_, type..., id] = key.split ":"
      type = type.join ":"

      status = "stuck"
      if activeJobs.keys[type] and id not in activeJobs.keys[type]
        status = "active"
      else if completedJobs.keys[type] and id not in completedJobs.keys[type]
        status = "complete"
      else if failedJobs.keys[type] and id not in failedJobs.keys[type]
        status = "failed"
      else if pendingJobs.keys[type] and id not in pendingJobs.keys[type]
        status = "pending"
      {id, type, status}

    keyList = keyList.sort (a, b) ->
      aid = parseInt a.id
      bid = parseInt b.id
      if aid < bid then -1
      else if aid > bid then 1
      else 0

    callback null, keyList

  commandRemoveFromStateLists: (prefix, id) -> [
    ["lrem", "#{prefix}active",     0, id]
    ["lrem", "#{prefix}wait",       0, id]
    ["srem", "#{prefix}completed",  id]
    ["srem", "#{prefix}failed",     id]
  ]

  #Removes one or  more jobs by ID, also removes the job from any state list it's in
  remove: (list) ->
    return unless list
    #Expects {id: 123, type: "video transcoding"}
    multi = []
    for item in list
      prefix = "bull:#{item.type}:"
      multi.push ["del", "#{prefix}#{item.id}"]
      multi.concat @commandRemoveFromStateLists prefix, item.id

    (@redis.multi multi).exec()

  #Makes all jobs in a specific status pending
  makePendingByType: (type, callback) ->
    type = type.toLowerCase()
    validTypes = [
      "active"
      "complete"
      "failed"
      "wait"
    ]
    #I could add stuck, but I won't support mass modifying "stuck" jobs because it's very possible for things to be in a "stuck" state temporarily, while transitioning between states

    return callback "Invalid type: #{type} not in list of supported types" unless type in validTypes
    ideally = errify callback

    await @statusKeys type, ideally defer allKeys
    multi = []
    for type, keys of allKeys.keys
      prefix = "bull:#{type}:"
      for id in keys
        multi.push ["rpush", "#{prefix}wait", id]
        multi.concat @commandRemoveFromStateLists prefix, id

    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully made all #{type} jobs pending."

  #Makes a job with a specific ID pending, requires the type of job as the first parameter and ID as second.
  makePendingById = (type, id, callback) ->
    return callback "id required"   unless id
    return callback "type required" unless type
    ideally = errify callback

    prefix = "bull:#{type}:"
    multi  = [["rpush", "#{prefix}wait", id]]
    multi.concat @commandRemoveFromStateLists prefix, id
    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully made #{type} job ##{id} pending."

  deleteByStatus: (type, callback) ->
    type = type.toLowerCase()
    validTypes = [
      "active"
      "complete"
      "failed"
      "wait"
    ]
    #I could add stuck, but I won't support mass modifying "stuck" jobs because it's very possible for things to be in a "stuck" state temporarily, while transitioning between states

    return callback "Invalid type: #{type} not in list of supported types" unless type in validTypes
    ideally = errify callback

    await @statusKeys type, ideally defer allKeys
    multi = []
    for type, keys of allKeys.keys
      prefix = "bull:#{type}:"
      for id in keys
        multi.push ["del", "#{prefix}#{id}"]
        multi.concat @commandRemoveFromStateLists prefix, id

    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully deleted all jobs of status #{type}."

  deleteById: (type, id, callback) ->
    return callback "id required"   unless id
    return callback "type required" unless type
    ideally = errify callback

    prefix = "bull:#{type}:"
    multi  = [["del", "#{prefix}#{id}"]]
    multi.concat @commandRemoveFromStateLists prefix, id
    await (@redis.multi multi).exec ideally defer data
    callback null, "Successfully deleted job #{type} ##{id}."

  dataById: (type, id, callback) ->
    return callback "id required"   unless id
    return callback "type required" unless type
    ideally = errify callback

    prefix = "bull:#{type}:"
    await redis.hgetall "#{prefix}id", ideally defer err, result
    callback null, result

  progressForKeys: (keys, callback) ->
    ideally = errify callback

    multi = for key in keys
      ["hget", "bull:#{key.type}:#{key.id}", "progress"]

    await (@redis.multi multi).exec ideally defer results
    key.progress = results[i] for key, i in keys
    callback null, keys


module.exports = RedisModel
