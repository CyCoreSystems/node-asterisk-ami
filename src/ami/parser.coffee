events = require 'events'
util = require 'util'

Parser = (socket)->
  events.EventEmitter.call this

  if not socket
    return @emit 'error','No socket passed to Parser'
  @socket = socket
  @socket.setEncoding 'ascii'
  @buffer = ''
  @lines = []
  @initialized = false

  # AMI protocol
  @separator = "\r\n"

  @socket.on 'data',@_onData.bind(this)
  @socket.on 'end',@_onEnd.bind(this)
  @on 'line',@_onLine.bind(this)
  @on 'message',@_onMessage.bind(this)

  return

util.inherits Parser,events.EventEmitter

Parser.prototype.flush = ->
  # Flush the buffer
  @buffer = ''
  @lines = []

Parser.prototype._onEnd = ->
  return

Parser.prototype._onData = (data)->
  self = this
  # Add the data to our buffer
  @buffer += data

  lines = data.split @separator

  # Prepend our first line with whatever
  # remnants were in the buffer
  lines[0] = @buffer + lines[0]

  # Bump back out to the buffer any partial
  # Note that this also absorbs the last separator.
  # In the case of AMI, this allows us to
  # process our buffered lines whenever a blank
  # line is encountered (because it would have
  # had to have been at least two separators)
  @buffer = lines.pop()

  lines.forEach (line)->
    self.emit 'line',line
  return

Parser.prototype._onLine = (line)->
  # Discard the first (preamble) line
  # and emit an 'ami:ready' event
  if not @initialized
    @initialized = 'true'
    @emit 'ami:ready'
    return
  # If we got a blank line, the
  # current message is complete,
  # so emit it and clear our line
  # buffer
  if not line
    @emit 'message',@lines.slice(0)
    @lines = []
  @lines.push line
  return
  
Parser.prototype._onMessage = (lines)->
  if not lines
    # Ignore empty message
    return
  # Parse the message
  message = @parse lines
  # If the message is an empty object,
  # silently do nothing
  if not Object.keys(message).length
    return
  # Emit parsed message
  @emit 'ami:message',message
  # Certain messages should have special events
  if message.Response
    @emit 'ami:response',message
  if message.Event
    @emit 'ami:event',message
  return

Parser.prototype.parse = Parser.prototype.toObj = (lines)->
  msg = {}
  lines.forEach (line)->
    tmp = line.split ':'
    if tmp.length < 2
      # Ignore lines which have no key-value pairs
      return
    key = tmp.shift()
    val = tmp.join ':'
    
    # If the key already exists in the msg,
    # convert it to an array
    if msg[key]
      if typeof msg[key] is 'array'
        msg[key].push val.trim()
      else
        msg[key] = [ msg[key], val.trim() ]
    else
      msg[key] = val.trim()
  return msg

Parser.prototype.toAMI = (obj)->
  self = this
  lines = []
  obj.forEach (val,key)->
    if typeof val is 'string'
      return lines.push [key,val].join ': '
    # Convert arrays to multiple lines
    # with the same key
    else if typeof val is 'array'
      val.forEach (item)->
        return lines.push [key,item].join ': '
    else
      self.emit 'error',"Unhandled type in toAMI:"+ typeof val
      return
    return
  return lines.join(@separator).concat @separator


module.exports =
  Parser: Parser
