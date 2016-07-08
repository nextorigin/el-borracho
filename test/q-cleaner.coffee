## https://github.com/OptimalBits/bull/issues/83
qCleaner = (queue) ->
  clean = queue.clean.bind queue, 0
  queue.pause()
       .then clean 'completed'
       .then clean 'active'
       .then clean 'delayed'
       .then clean 'failed'
       .then -> queue.empty()
       # .then -> queue.close()


module.exports = qCleaner
