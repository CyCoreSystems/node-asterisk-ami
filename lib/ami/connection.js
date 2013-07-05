var Connection, EventEmitter, Logger, Parser, net, util, uuid, _;

_ = require('underscore')._;

uuid = require('node-uuid');

util = require('util');

EventEmitter = require('events').EventEmitter;

net = require('net');

Logger = require('./logger');

Parser = require('./parser').Parser;

Connection = function(options, cb) {
  var self, _ref;
  self = this;
  this.options = _.extend({
    host: 'localhost',
    port: 5038,
    username: '',
    password: '',
    debug: false,
    reconnect: false,
    reconnect_after: 3000,
    events: true,
    raw: false
  }, options);
  if (cb) {
    if (typeof cb === 'function') {
      this.options.ready_cb = cb;
    }
  }
  if (this.options.events) {
    this.options.events = 'on';
  } else {
    this.options.events = 'off';
  }
  if ((_ref = opts.secret) != null ? _ref.length : void 0) {
    this.options.password = opts.secret;
  }
  if (!options.logger) {
    options.logger = Logger.createLogger(this.options.debug);
  }
  this.log = options.logger;
  this.loggedin = false;
  this.socket = net.connect({
    port: this.options.port,
    host: this.options.host
  }, this._onConnect.bind(this));
  this.socket.on('ready', function() {
    return self.login(function(err) {
      if (err != null) {
        return self.emit('error', "Failed login: " + err);
      }
      self.loggedin = true;
      return self.emit('ami:login');
    });
  });
  this.socket.on('error', this._onError.bind(this));
  this.socket.on('end', this._onEnd.bind(this));
};

util.inherits(Connection, EventEmitter);

Connection.prototype.send = function(command) {
  var err;
  if (typeof command !== 'string') {
    command = Parser.toAMI(command);
  }
  try {
    this.socket.write(command + "\r\n\r\n");
  } catch (_error) {
    err = _error;
    this.emit('error', err);
  }
};

/*
# Generic AMI Actions have an ActionID field
# to track their execution response, so this
# is a wrapper to add the ActionID header
# and bind the callback to its response
*/


Connection.prototype.action = function(action, args, cb) {
  var opts;
  if (typeof args === 'function') {
    cb = args;
    args = null;
  }
  opts = {
    ActionID: uuid.v1()
  };
  if (args != null) {
    opts = _.extend(opts, args);
  }
  if (typeof action === 'string') {
    opts.Action = action;
  } else if (typeof action === 'object') {
    opts = _.extend(opts, action);
  }
  if (!opts.Action) {
    return typeof cb === "function" ? cb("An action must contain an Action") : void 0;
  }
  if (cb != null) {
    this.actionQueue[opts.ActionID] = cb;
  }
  this.send(opts);
};

/*
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
*/


Connection.prototype.agi = function(command, args, cb) {
  var opts;
  if (typeof args === 'function') {
    cb = args;
    args = null;
  }
  opts = {
    Action: 'AGI',
    ActionID: uuid.v1(),
    CommandID: uuid.v1()
  };
  if (args != null) {
    opts = _.extend(opts, args);
  }
  if (typeof command === 'string') {
    opts.Command = command;
  } else if (typeof command === 'object') {
    opts = _.extend(opts, command);
  }
  if (cb != null) {
    this.actionQueue[opts.ActionID] = cb;
  }
  if (opts.complete != null) {
    this.agiQueue[opts.CommandID] = opts.complete;
  }
  this.send(opts);
};

/*
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
*/


Connection.prototype.originate = function(args, cb) {
  var opts;
  if (typeof args === 'function') {
    cb = args;
    args = null;
  }
  opts = _.extend({
    Action: 'Originate',
    ActionID: uuid.v1(),
    Async: 'true',
    sync: false
  }, args);
  if ((opts.sync != null) && (cb != null)) {
    this.originateQueue[opts.ActionID] = {
      complete: cb
    };
  } else if ((opts.complete != null) || (cb != null)) {
    if (cb != null) {
      this.actionQueue[opts.ActionID] = cb;
    }
    if (opts.complete != null) {
      this.originateQueue[opts.ActionID] = opts.complete;
    }
  }
  this.send(opts);
};

Connection.prototype.login = function(cb) {
  var req;
  req = {
    Action: 'Login',
    Username: this.options.username,
    Secret: this.options.password
  };
  return this.action(req, cb);
};

Connection.prototype._onConnect = function() {
  this.parser = new Parser(this.socket);
  this.parser.on('ami:message', this._onMessage.bind(this));
  this.parser.on('error', this._onError.bind(this));
  return this.emit('connect');
};

Connection.prototype._onMessage = function(message) {
  this.emit('ami:message', message);
  if ((message.Event === 'Response') && message.ActionID) {
    this.emit('ami:response', message);
  }
  if ((message.Event === 'AsyncAGI') && message.CommandID) {
    return this.emit('ami:agi', message);
  }
};
