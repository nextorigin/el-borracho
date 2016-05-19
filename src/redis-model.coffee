# https://github.com/petkaantonov/bluebird/issues/63#issuecomment-34140791
_ = require("lodash")
q = require("bluebird")

class RedisModel
  constructor: (@redis) ->

  getActiveKeys: (callback) ->
    @redis.keys "bull:*:active", callback

  getCompletedKeys: (callback) ->
    @redis.keys "bull:*:completed", callback

  getFailedKeys: (callback) ->
    @redis.keys "bull:*:failed", callback

  getWaitingKeys: (callback) ->
    @redis.keys "bull:*:wait", callback

  getStuckKeys: (callback) ->
    ideally = errify callback
    #TODO: Find better way to do this. Being lazy at the moment.
    await getAllKeys ideally defer keys
    await formatKeys keys, ideally defer keyList

    count = 0
    keys  = {}
    for key in keyList when key.status is stuck
      results[keyList[i].type] or= []
      results[keyList[i].type].push keyList[i].id
      count++

    callback null, {keys, count}

  #Returns indexes of completed jobs
  getStatus: (status, callback) ->
    ideally = errify callback

    getStatusKeysFunction = switch status
    when "complete" then getCompletedKeys
    when "active"   then getActiveKeys
    when "failed"   then getFailedKeys
    when "wait"     then getWaitingKeys
    when "stuck"    then getStuckKeys()
    else
      return callback new Error "UNSUPPORTED STATUS: #{status}"

    await getStatusKeysFunction ideally defer statusKeys

    keys = []
    multi = []

    for key in statusKeys
      keys[(key.split ":")[1]] = []
      # This creates an array/object thing with keys of the job type
      if status is "active" or status is "wait"
        multi.push ["lrange", key, 0, -1]
      else
        multi.push ["smembers", key]

    await (@redis.multi multi).exec ideally defer data
    statusKeyKeys = Object.keys(keys)
    # Get the keys from the object we created earlier...
    count = 0
    for datum, i in data
      keys[statusKeyKeys[i]] = datum
      count += datum.length

    callback null, {keys, count}

  #Returns all JOB keys in string form (ex: bull:video transcoding:101)
  getAllKeys = (callback) ->
    ideally = errify callback
    await @redis.keys "bull:*:[0-9]*" ideally defer keysWithLocks
    (keyWithLock for keyWithLock in keysWithLocks when keyWithLock.substring(keyWithLock.length - 5, keyWithLock.length) isnt ":lock")

  getFullKeyNamesFromIds = (list, callback) ->
    return callback() unless list and Array.isArray list

    ideally = errify callback
    keys = (["keys", "bull:*:#{item}"] for item in list)
    await @redis.multi(keys).exec ideally defer arrayOfArrays
    callback null, (array[0] for array in arrayOfArrays when array.length is 1)

  #Returns the job data from a list of job ids
  getJobsInList = (list) ->
    return callback() unless list

    ideally = errify callback
    jobs = []
    if keys = list.keys
      objectKeys = Object.keys(keys)
      fullNames = []

      for key, val in keys
        for i in val
          fullNames.push "bull:" + key + ":" + keys[objectKeys[i]][k]
      callback null, fullnames
    else
      #Old list type
      getFullKeyNamesFromIds list, callback

  #Returns counts for different statuses
  getStatusCounts = (callback) ->
    ideally = errify callback
    await getStatus "active",   ideally defer active
    await getStatus "complete", ideally defer completed
    await getStatus "failed",   ideally defer failed
    await getStatus "wait",     ideally defer pendingKeys
    await getAllKeys ideally defer allKeys

    active: active.count
    complete: completed.count
    failed: failed.count
    pending: pendingKeys.count
    total: allKeys.length
    stuck: allKeys.length - (active.count + completed.count + failed.count + pendingKeys.count)

  #Returns all keys in object form, with status applied to object. Ex: {id: 101, type: "video transcoding", status: "pending"}
  formatKeys = (keys, callback) ->
    return unless keys

    ideally = errify callback

    await getStatus "failed",   ideally defer failedJobs
    await getStatus "complete", ideally defer completedJobs
    await getStatus "active",   ideally defer activeJobs
    await getStatus "wait",     ideally defer pendingJobs

    keyList = for key in keys
      [type, id] = key.split ":"
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

    keyList = _.sortBy keyList, (key) -> parseInt key.id
    callback null, keyList

  #Removes one or  more jobs by ID, also removes the job from any state list it"s in
  removeJobs = (list) ->
    return unless list
    #Expects {id: 123, type: "video transcoding"}
    multi = []
    for item in list
      firstPartOfKey = "bull:#{item.type}:"
      multi.push ["del",  firstPartOfKey + item.id]
      multi.push ["lrem", firstPartOfKey + "active", 0, .id]
      multi.push ["lrem", firstPartOfKey + "wait", 0, .id]
      multi.push ["srem", firstPartOfKey + "completed", item.id]
      multi.push ["srem", firstPartOfKey + "failed", item.id]

    (@redis.multi multi).exec()

  #Makes all jobs in a specific status pending
  makePendingByType = (type, callback) ->
    type = type.toLowerCase()
    validTypes = [
      "active"
      "complete"
      "failed"
      "wait"
    ]
    #I could add stuck, but(callback)  I won"t support mass modifying "stuck" jobs because it"s very possible for things to be in a "stuck" state temporarily, while transitioning between states

    ideally = errify (message) -> callback {success: false, message}

    console.log validTypes.indexOf(type)
    unless type in validTypes
      return callback success: false, message: "Invalid type: #{type} not in list of supported types"

    await getStatus type, ideally defer allKeys
      multi = []
      allKeyObjects = Object.keys(allKeys.keys)

      i = 0
      ii = allKeyObjects.length
      while i < ii
        firstPartOfKey = "bull:" + allKeyObjects[i] + ":"
        k = 0
        kk = allKeys.keys[allKeyObjects[i]].length
        while k < kk
          item = allKeys.keys[allKeyObjects[i]][k]
          #Brute force remove from everything
          multi.push ["lrem", firstPartOfKey + "active", 0, item]
          multi.push ["srem", firstPartOfKey + "completed", item]
          multi.push ["srem", firstPartOfKey + "failed", item]
          #Add to pending
          multi.push ["rpush", firstPartOfKey + "wait", item]

      await (@redis.multi multi).exec ideally defer data
      callback success: true, message: "Successfully made all #{type} jobs pending."

  #Makes a job with a specific ID pending, requires the type of job as the first parameter and ID as second.
  makePendingById = (type, id, callback) ->
    unless id
      return callback success: false, message: "There was no ID provided."
    unless type
      return callback success: false, message: "There was no type provided."

    ideally = errify (message) -> callback {success: false, message}

    firstPartOfKey = "bull:#{type}:"

    multi = []
    multi.push ["lrem", firstPartOfKey + "active", 0, id]
    multi.push ["lrem", firstPartOfKey + "wait", 0, id]
    multi.push ["srem", firstPartOfKey + "completed", id]
    multi.push ["srem", firstPartOfKey + "failed", id]
    #Add to pending
    multi.push ["rpush", firstPartOfKey + "wait", id]
    await (@redis.multi multi).exec ideally defer data
    callback success: true, message: "Successfully made #{type} job ##{id} pending."

  #Deletes all jobs in a specific status
  deleteJobByStatus = (type, callback) ->
    type = type.toLowerCase()
    validTypes = [
      "active"
      "complete"
      "failed"
      "wait"
    ]
    #I could add stuck, but(callback)  I won"t support mass modifying "stuck" jobs because it"s very possible for things to be in a "stuck" state temporarily, while transitioning between states

    unless type in validTypes
      return callback success: false, message: "Invalid type: #{type} not in list of supported types"

    ideally = errify (message) -> callback {success: false, message}

    allKeyObjects = Object.keys(allKeys.keys)
    i = 0
    ii = allKeyObjects.length
    while i < ii
      firstPartOfKey = "bull:" + allKeyObjects[i] + ":"
      k = 0
      kk = allKeys.keys[allKeyObjects[i]].length
      while k < kk
        item = allKeys.keys[allKeyObjects[i]][k]
        #Brute force remove from everything
        multi.push ["lrem", firstPartOfKey + "active", 0, item]
        multi.push ["lrem", firstPartOfKey + "wait", 0, item]
        multi.push ["srem", firstPartOfKey + "completed", item]
        multi.push ["srem", firstPartOfKey + "failed", item]
        multi.push ["del",  firstPartOfKey + item]

    await (@redis.multi multi).exec ideally defer data
    callback success: true, message: "Successfully deleted all jobs of status #{type}."

  #Deletes a job by ID. Requires type as the first parameter and ID as the second.
  deleteJobById = (type, id, callback) ->
    unless id
      return callback success: false, message: "There was no ID provided."
    unless type
      return callback success: false, message: "There was no type provided."

    ideally = errify (message) -> callback {success: false, message}

    firstPartOfKey = "bull:#{type}:"
    multi = []
    multi.push ["lrem", firstPartOfKey + "active", 0, id]
    multi.push ["lrem", firstPartOfKey + "wait", 0, id]
    multi.push ["srem", firstPartOfKey + "completed", id]
    multi.push ["srem", firstPartOfKey + "failed", id]
    multi.push ["del", firstPartOfKey + id]
    await (@redis.multi multi).exec ideally defer data
    callback null, success: true, message: "Successfully deleted job #{type} ##{id}."

  #Gets the progress for the keys passed in
  getProgressForKeys = (keys, callback) ->
    ideally = errify callback
    multi = []

    for key in keys
      multi.push ["hget", "bull:" + key.type + ":" + key.id, "progress"]

    await (@redis.multi multi).exec ideally defer results
      `var i`
      `var ii`
      i = 0
      ii = keys.length
      while i < ii
        key.progress = results[i]


module.exports = RedisModel
