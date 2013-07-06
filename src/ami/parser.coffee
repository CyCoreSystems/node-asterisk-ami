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
    # Message was an acknowledgement of an AMI command
    @emit 'ami:response',message
  if message.Event
    # Message was an Event
    @emit 'ami:event',message
    if message.Event is 'AsyncAGI'
      if message.SubEvent is 'Start'
        # This is the start of an AGI command (or session)
        @emit 'ami:agi:start',message
        # Pass to _onAGIStart for further parsing
        @_onAGIStart message
      if message.SubEvent is 'End'
        # This is the end of an AGI command (or session)
        @emit 'ami:agi:end',message
        # Pass to _onAGIEnd for further parsing
        @_onAGIEnd message
      if message.SubEvent is 'Exec'
        # Message was a response to an AsyncAGI call
        @emit 'ami:agi:exec',message
    if message.Event is 'OriginateResponse'
      # Message was a response to an Originate call
      @emit 'ami:originate',message
  return

Parser.prototype._onAGIStart = (message)->
  if message.Command
    # Start of AsyncAGI command execution
    # NOTE: the CommandId here does not match
    # the CommandID passed with the AGI command;
    # therefore, it is unclear to the author
    # the it is at all useful to reemit this
    # event.  This is implemented for completeness
    # only.
    return @emit 'ami:agi:command:start',message
  # Start of AsyncAGI session
  message.Env = @parseEnv message.Env
  return @emit 'ami:agi:session:start',message

Parser.prototype._onAGIEnd = (message)->
  if message.Command
    # End of AsyncAGI command execution
    # NOTE: the CommandId here does not match
    # the CommandID passed with the AGI command;
    # therefore, it is unclear to the author
    # the it is at all useful to reemit this
    # event.  This is implemented for completeness
    # only.
    return @emit 'ami:agi:command:end',message
  # End of AsyncAGI session
  return @emit 'ami:agi:session:end',message

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

Parser.prototype.parseEnv = (env)->
  # Environment variable string is
  # URI-encoded.  Split into lines
  # then key-value pairs.
  # Return as an object whose properties
  # are those key-value pairs
  ret = {}
  lines = env.split '%0A'
  _.each lines,(line)->
    pieces = line.split '%3A%20'
    ret[pieces[0]] = pieces[1]
  return ret

module.exports =
  Parser: Parser
