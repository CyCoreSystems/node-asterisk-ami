AMI = require '../../lib'
net = require 'net'
fs = require 'fs'
path = require 'path'

testSocket = 50556
testSrc = "../events"
testTimeout = 100

# Create echo server
testServer = net.createServer (c)->
  c.pipe c

# inject the test
injectTest = (socket,name)->
  return socket.write fs.readFileSync path.resolve __dirname,testSrc,name+".event"

exports.setUp = (cb)->
  self = this
  testServer.listen testSocket,->
    self.parser = new AMI.Parser net.createConnection { port: testSocket }
    self.parser.socket.once 'connect',->
      return cb()
  return

exports.tearDown = (cb)->
  @parser.socket.destroy()
  testServer.close()
  return cb()

exports['Verify socket exists'] = (test)->
  test.ok @parser.socket?
  return test.done()

exports['Emits ami:ready on first line'] = (test)->
  to = setTimeout ->
    test.ok false,"Timed out"
    return test.done()
  ,testTimeout
  @parser.once 'ami:ready',->
    clearTimeout to
    test.ok true
    return test.done()
  injectTest @parser.socket,'primer'

exports.LineDetection =
  setUp: (cb)->
    @parser.initialized = true
    @parser.flush()
    return cb()
  'Emits a line': (test)->
    to = setTimeout ->
      test.ok false,"Timed out"
      return test.done()
    ,testTimeout
    @parser.once 'line',(line)->
      clearTimeout to
      test.ok (line.length > 1)
      return test.done()
    injectTest @parser.socket,'invalid-line'
  'Does not emit partial line': (test)->
    to = setTimeout ->
      test.ok true
      return test.done()
    ,testTimeout
    @parser.once 'line',(line)->
      clearTimeout to
      test.ok false,"Detected line from partial"
      return test.done()
    injectTest @parser.socket,'partial-line'
  'Emits message on full event': (test)->
    to = setTimeout ->
      test.ok false,"Timed out"
      return test.done()
    ,testTimeout
    @parser.once 'message',(line)->
      clearTimeout to
      test.ok (line.length > 1)
      return test.done()
    injectTest @parser.socket,'valid-event'
  'Does not emit message on partial event': (test)->
    to = setTimeout ->
      test.ok true
      return test.done()
    ,testTimeout
    @parser.once 'message',(line)->
      clearTimeout to
      test.ok false,"Detected message from partial"
      return test.done()
    injectTest @parser.socket,'partial-event'


exports.EventParsing =
  setUp: (cb)->
    @parser.initialized = true
    @parser.flush()
    return cb()
  'Emits valid ami:message on valid event': (test)->
    to = setTimeout ->
      test.ok false,"Timed out"
      return test.done()
    ,testTimeout
    @parser.once 'ami:message',(message)->
      clearTimeout to
      test.ok (Object.keys(message).length > 0)
      return test.done()
    injectTest @parser.socket,'valid-event'
  'Does not emit ami:message on empty event': (test)->
    to = setTimeout ->
      test.ok true
      return test.done()
    ,testTimeout
    @parser.once 'ami:message',(message)->
      clearTimeout to
      test.ok false,"Emitted ami:message on empty event"
      return test.done()
    injectTest @parser.socket,'empty-event'
  'Emits ami:response on response event': (test)->
    to = setTimeout ->
      test.ok false,"Timed out"
      return test.done()
    ,testTimeout
    @parser.once 'ami:response',(message)->
      clearTimeout to
      test.ok message.Response?
      return test.done()
    injectTest @parser.socket,'valid-response'
  'Emits ami:event on Event event': (test)->
    to = setTimeout ->
      test.ok false,"Timed out"
      return test.done()
    ,testTimeout
    @parser.once 'ami:event',(message)->
      clearTimeout to
      test.ok message.Event?
      return test.done()
    injectTest @parser.socket,'valid-event'




