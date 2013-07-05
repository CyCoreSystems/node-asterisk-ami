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
    reconnect: false
    reconnect_after: 3000
    events: true
    raw: false
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
  if opts.secret?.length
    @options.password = opts.secret

  # Bind our logger
  if not options.logger
    options.logger = Logger.createLogger @options.debug
  @log = options.logger
    
  @loggedin = false

  @socket = net.connect {
    port: @options.port
    host: @options.host
  },@_onConnect.bind(this)

  @socket.on 'ready',->
    self.login (err)->
      if err?
        return self.emit 'error',"Failed login: #{err}"
      self.loggedin = true
      self.emit 'ami:login'

  @socket.on 'error',@_onError.bind(this)

  @socket.on 'end',@_onEnd.bind(this)

  return

util.inherits Connection,EventEmitter

Connection.prototype.send = (command)->
  if typeof command isnt 'string'
    command = Parser.toAMI command
  try
    @socket.write command + "\r\n\r\n"
  catch err
    @emit 'error',err
  return

###
# Generic AMI Actions have an ActionID field
# to track their execution response, so this
# is a wrapper to add the ActionID header
# and bind the callback to its response
###
Connection.prototype.action = (action,args,cb)->
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
Connection.prototype.agi = (command,args,cb)->
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
Connection.prototype.originate = (args,cb)->
  if typeof args is 'function'
    cb = args
    args = null
  opts = _.extend {
    Action: 'Originate'
    ActionID: uuid.v1()
    Async: 'true'
    sync: false
  },args
  if (opts.sync?) and (cb?)
    @originateQueue[opts.ActionID] =
      complete: cb
  else if (opts.complete?) or (cb?)
    if cb?
      @actionQueue[opts.ActionID] = cb
    if opts.complete?
      @originateQueue[opts.ActionID] = opts.complete
  @send opts
  return

Connection.prototype.login = (cb)->
  req =
    Action: 'Login'
    Username: @options.username
    Secret: @options.password
  @action req,cb

Connection.prototype._onConnect = ->
  @parser = new Parser @socket
  @parser.on 'ami:message',@_onMessage.bind(this)
  @parser.on 'error',@_onError.bind(this)
  @emit 'connect'

Connection.prototype._onMessage = (message)->
  # Always emit the message itself
  @emit 'ami:message',message
  # Handle special message types
  if (message.Event is 'Response') and message.ActionID
    @emit 'ami:response',message
  if (message.Event is 'AsyncAGI') and message.CommandID
    @emit 'ami:agi',message
