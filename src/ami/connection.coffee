_ = require('underscore')._
uuid = require 'node-uuid'
util = require 'util'
EventEmitter = require('events').EventEmitter
net = require 'net'

Logger = require './logger'
Parser = require('./parser').Parser

Connection = (options,cb)->
  self = this
  @options = _.extend {
    host: 'localhost'
    port: 5038
    username: ''
    password: ''
    debug: false
    events: true
  },options

  # If the passed a callback, bind it to ready_cb
  if cb
    if typeof cb is 'function'
      @options.ready_cb = cb

  # Convert events boolean to AMI string
  if @options.events
    @options.events = 'on'
  else
    @options.events = 'off'

  # Use secret instead of password, if provided
  if options.secret?.length
    @options.password = options.secret

  # Bind our logger
  if not options.logger
    options.logger = Logger.createLogger @options.debug
  @log = options.logger
    
  @loggedin = false

  # Create our command response callback queues
  @actionQueue = []
  @agiQueue = []
  @originateQueue = []

  @socket = net.connect {
    port: @options.port
    host: @options.host
  },@_onConnect.bind(this)

  @socket.on 'error',@_onError.bind(this)

  @socket.on 'end',@_onEnd.bind(this)

  return

util.inherits Connection,EventEmitter

Connection.prototype.send = (command)->
  if typeof command isnt 'string'
    command = @parser.toAMI command
  try
    @socket.write command
  catch err
    @_onError "Failed to send: #{err}"
  return

###
# Generic AMI Actions have an ActionID field
# to track their execution response, so this
# is a wrapper to add the ActionID header
# and bind the callback to its response
###
Connection.prototype.action = Connection.prototype.Action = (action,args,cb)->
  if typeof args is 'function'
    cb = args
    args = null
  opts =
    ActionID: uuid.v1()
  if args?
    opts = _.extend opts,args
  if typeof action is 'string'
    opts.Action = action
  else if typeof action is 'object'
    opts = _.extend opts,action
  if not opts.Action
    return cb? "An action must contain an Action"
  if cb?
    @actionQueue[opts.ActionID] = cb
  @send opts
  return

###
# Async AGI calls have an additional
# CommandID for tracking, so this is
# a wrapper to add the CommandID header
#
# Note that the parameter-passed callback
# will be called when AMI _accepts_ the
# AGI command.
# If you want another callback to be called
# when the AGI command is complete, then
# pass it as the 'complete' property of
# the args parameter.
###
Connection.prototype.agi = Connection.prototype.AGI = (command,args,cb)->
  if typeof args is 'function'
    cb = args
    args = null
  opts = {
    Action: 'AGI'
    ActionID: uuid.v1()
    CommandID: uuid.v1()
  }
  if args?
    opts = _.extend opts,args
  if typeof command is 'string'
    opts.Command = command
  else if typeof command is 'object'
    opts = _.extend opts,command
  if cb?
    @actionQueue[opts.ActionID] = cb
  if opts.complete?
    @agiQueue[opts.CommandID] = opts.complete
  @send opts
  return

###
# AMI Originate blocks the entire AMI
# socket unless the Async flag is set
# Therefore, we provide an originate wrapper
# which _always_ passes the Async flag.
# If you want want to only call the callback
# on completion of the Originate action,
# pass "sync: true" in the arguments parameter
# object.  Originate will still be called
# asynchronously to AMI, but the callback won't
# be called until completion of the Originate
# command.
# The default behaviour is to call the callback
# on _acceptance_ of the Originate action.
# You may pass the 'complete' property to provide
# a callback on completion of the Originate action.
###
Connection.prototype.originate = Connection.prototype.Originate = (args,cb)->
  opts = _.extend {
    Action: 'Originate'
    ActionID: uuid.v1()
    Async: 'true'
    sync: false
  },args
  if opts.Variable
    if typeof opts.Variable is 'object'
      # Convert variable object to array
      vars = []
      _.each opts.Variable,(val,key)->
        vars.push key+"="+val
      opts.Variable = vars
  if (opts.sync) and (cb?)
    @originateQueue[opts.ActionID] = cb
  else if (opts.complete?) or (cb?)
    if cb?
      @actionQueue[opts.ActionID] = cb
    if opts.complete?
      @originateQueue[opts.ActionID] = opts.complete
  @send opts
  return

Connection.prototype.login = Connection.prototype.Login = (cb)->
  req =
    Action: 'Login'
    Username: @options.username
    Secret: @options.password
  @action req,cb

Connection.prototype.getVar = Connection.prototype.GetVar = (channel,key,cb)->
  req =
    Action: 'GetVar'
    Channel: channel
    Variable: key
  @action req,(err,mesg)->
    if mesg?.Response isnt 'Success'
      return cb? "Failed to get variable",mesg
    return cb? null,mesg.Value

Connection.prototype._onConnect = ->
  self = this
  @log.trace "Connected to Asterisk AMI"
  @parser = new Parser {
    socket: @socket
    logger: @log
  }
  @parser.on 'ami:message',@_onMessage.bind(this)
  @parser.on 'ami:response',@_onResponse.bind(this)
  @parser.on 'ami:event',@_onEvent.bind(this)
  @parser.on 'ami:agi:exec',@_onAgiExec.bind(this)
  @parser.on 'ami:agi:session:start',(message)->
    self.log.trace "Got AsyncAGI Session Start",message
    return self.emit 'agi:start',message
  @parser.on 'ami:agi:session:end',(message)->
    self.log.trace "Got AsyncAGI Session End",message
    return self.emit 'agi:end',message
  @parser.on 'ami:originate',@_onOriginate.bind(this)
  @parser.on 'error',@_onError.bind(this)
  @emit 'connect'
  # Log in
  self.log.trace "Socket ready"
  self.login (err)->
    self.log.trace "Received login response"
    if err?
      self.log.error "Failed login"
      return self.emit 'ami:login:failed'
    self.loggedin = true
    self.emit 'ami:login'

Connection.prototype._onEnd = ->
  @log.info "Connection ended"
  return @emit 'end'

Connection.prototype._onError = (message)->
  @log.error message
  return

Connection.prototype._onMessage = (message)->
  # Reemit to self
  @emit 'message',message

Connection.prototype._onResponse = (message)->
  @log.trace "Response received:",message
  if not message.ActionID
    return
  @emit "response:#{message.ActionID}",message
  if message.Event is 'OriginateResponse'
    # Ignore OriginateResponses here; they
    # are handled separately.  Reemitting here
    # could potentially cause glare, if the
    # OriginateResponse is handled before the
    # acknowledgement callback is removed
    # from the action queue, thus calling
    # the acknowledgement callback twice.
    return
  cb = @actionQueue[message.ActionID]
  delete @actionQueue[message.ActionID]
  if typeof cb is 'function'
    if message.Response isnt 'Success'
      return cb? message.Message,message
    return cb? null,message
  return

Connection.prototype._onEvent = (message)->
  if message?.Event
    @emit "event:#{message.Event}",message
  if message?.ActionID
    @emit "event:#{message.ActionID}",message
  return

Connection.prototype._onAgiExec = (message)->
  if not message.CommandID
    return
  @emit "agi:exec:#{message.CommandID}",message
  cb = @agiQueue[message.CommandID]
  delete @agiQueue[message.CommandID]
  if typeof cb is 'function'
    cb null,message
  return

Connection.prototype._onOriginate = (message)->
  if not message.ActionID
    return
  @emit "originate:#{message.ActionID}",message
  cb = @originateQueue[message.ActionID]
  delete @originateQueue[message.ActionID]
  if typeof cb is 'function'
    if message.Response isnt 'Success'
      return cb "Origination Failed: #{message.Reason}",message
    return cb null,message
  return

module.exports =
  Connection: Connection
