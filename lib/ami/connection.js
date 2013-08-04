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
    events: true,
    reconnectTimeout: 5000
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
  if ((_ref = options.secret) != null ? _ref.length : void 0) {
    this.options.password = options.secret;
  }
  if (!options.logger) {
    options.logger = Logger.createLogger(this.options.debug);
  }
  this.log = options.logger;
  this.loggedin = false;
  this.actionQueue = [];
  this.agiQueue = [];
  this.originateQueue = [];
  this.connect();
  _.bindAll(this);
};

util.inherits(Connection, EventEmitter);

Connection.prototype.connect = function(port, host, cb) {
  var connhost, connport, self;
  self = this;
  if (this.socket) {
    this.socket.removeAllListeners();
    this.socket = null;
  }
  if (this.parser) {
    this.parser.end();
    this.parser = null;
  }
  connport = this.options.port;
  connhost = this.options.host;
  if (port) {
    if (typeof port !== 'function') {
      if (typeof port === 'object') {
        if (port.port) {
          connport = port.port;
        }
        if (port.host) {
          connhost = port.host;
        }
      } else {
        connport = port;
      }
    } else {
      cb = port;
    }
    if (host) {
      if (typeof host !== 'function') {
        connhost = host;
      } else {
        cb = host;
      }
    }
  }
  this.socket = net.connect({
    port: connport,
    host: connhost
  }, function(err) {
    self._onConnect();
    return typeof cb === "function" ? cb(err) : void 0;
  });
  this.socket.on('error', this._onError.bind(this));
  this.socket.on('close', this._onClose.bind(this));
};

Connection.prototype.send = function(command) {
  var err;
  if (typeof command !== 'string') {
    command = this.parser.toAMI(command);
  }
  try {
    this.socket.write(command);
  } catch (_error) {
    err = _error;
    this._onError("Failed to send: " + err);
  }
};

/*
# Generic AMI Actions have an ActionID field
# to track their execution response, so this
# is a wrapper to add the ActionID header
# and bind the callback to its response
*/


Connection.prototype.action = Connection.prototype.Action = function(action, args, cb) {
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


Connection.prototype.agi = Connection.prototype.AGI = function(command, args, cb) {
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


Connection.prototype.originate = Connection.prototype.Originate = function(args, cb) {
  var opts, vars;
  opts = _.extend({
    Action: 'Originate',
    ActionID: uuid.v1(),
    Async: 'true',
    sync: false
  }, args);
  if (opts.Variable) {
    if (typeof opts.Variable === 'object') {
      vars = [];
      _.each(opts.Variable, function(val, key) {
        return vars.push(key + "=" + val);
      });
      opts.Variable = vars;
    }
  }
  if (opts.sync && (cb != null)) {
    this.originateQueue[opts.ActionID] = cb;
    delete opts.sync;
  } else if ((opts.complete != null) || (cb != null)) {
    if (cb != null) {
      this.actionQueue[opts.ActionID] = cb;
    }
    if (opts.complete != null) {
      this.originateQueue[opts.ActionID] = opts.complete;
      delete opts.complete;
    }
  }
  this.send(opts);
};

Connection.prototype.login = Connection.prototype.Login = function(cb) {
  var req;
  req = {
    Action: 'Login',
    Username: this.options.username,
    Secret: this.options.password
  };
  return this.action(req, cb);
};

Connection.prototype.getVar = Connection.prototype.GetVar = function(channel, key, cb) {
  var req;
  req = {
    Action: 'GetVar',
    Channel: channel,
    Variable: key
  };
  return this.action(req, function(err, mesg) {
    if ((mesg != null ? mesg.Response : void 0) !== 'Success') {
      return typeof cb === "function" ? cb("Failed to get variable", mesg) : void 0;
    }
    return typeof cb === "function" ? cb(null, mesg.Value) : void 0;
  });
};

Connection.prototype.setVar = Connection.prototype.SetVar = function(channel, key, val, cb) {
  var req;
  req = {
    Action: 'SetVar',
    Channel: channel,
    Variable: key,
    Value: val
  };
  return this.action(req, function(err, mesg) {
    if ((mesg != null ? mesg.Response : void 0) !== 'Success') {
      return typeof cb === "function" ? cb("Failed to set variable", mesg) : void 0;
    }
    return typeof cb === "function" ? cb(null) : void 0;
  });
};

Connection.prototype._onConnect = function() {
  var self;
  self = this;
  this.log.trace("Connected to Asterisk AMI");
  this.parser = new Parser({
    socket: this.socket,
    logger: this.log
  });
  this.parser.on('ami:message', this._onMessage.bind(this));
  this.parser.on('ami:response', this._onResponse.bind(this));
  this.parser.on('ami:event', this._onEvent.bind(this));
  this.parser.on('ami:agi:exec', this._onAgiExec.bind(this));
  this.parser.on('ami:agi:session:start', function(message) {
    self.log.trace("Got AsyncAGI Session Start", message);
    return self.emit('agi:start', message);
  });
  this.parser.on('ami:agi:session:end', function(message) {
    self.log.trace("Got AsyncAGI Session End", message);
    return self.emit('agi:end', message);
  });
  this.parser.on('ami:originate', this._onOriginate.bind(this));
  this.parser.on('error', this._onError.bind(this));
  this.emit('connect');
  self.log.trace("Socket ready");
  return self.login(function(err) {
    self.log.trace("Received login response");
    if (err != null) {
      self.log.error("Failed login");
      return self.emit('ami:login:failed');
    }
    self.loggedin = true;
    return self.emit('ami:login');
  });
};

Connection.prototype._onClose = function() {
  if (this.options.reconnectTimeout) {
    this.log.info("Connection ended; reconnecting in", this.options.reconnectTimeout, "ms");
    return setTimeout(this.connect, this.options.reconnectTimeout);
  } else {
    this.log.info("Connection ended");
  }
  return this.emit('end');
};

Connection.prototype._onError = function(message) {
  this.log.error(message);
};

Connection.prototype._onMessage = function(message) {
  return this.emit('message', message);
};

Connection.prototype._onResponse = function(message) {
  var cb;
  this.log.trace("Response received:", message);
  if (!message.ActionID) {
    return;
  }
  this.emit("response:" + message.ActionID, message);
  if (message.Event === 'OriginateResponse') {
    return;
  }
  cb = this.actionQueue[message.ActionID];
  delete this.actionQueue[message.ActionID];
  if (typeof cb === 'function') {
    if (message.Response !== 'Success') {
      return typeof cb === "function" ? cb(message.Message, message) : void 0;
    }
    return typeof cb === "function" ? cb(null, message) : void 0;
  }
};

Connection.prototype._onEvent = function(message) {
  if (message != null ? message.Event : void 0) {
    this.emit("event:" + message.Event, message);
  }
  if (message != null ? message.ActionID : void 0) {
    this.emit("event:" + message.ActionID, message);
  }
};

Connection.prototype._onAgiExec = function(message) {
  var cb;
  if (!message.CommandID) {
    return;
  }
  this.emit("agi:exec:" + message.CommandID, message);
  cb = this.agiQueue[message.CommandID];
  delete this.agiQueue[message.CommandID];
  if (typeof cb === 'function') {
    cb(null, message);
  }
};

Connection.prototype._onOriginate = function(message) {
  var cb;
  if (!message.ActionID) {
    return;
  }
  this.emit("originate:" + message.ActionID, message);
  cb = this.originateQueue[message.ActionID];
  delete this.originateQueue[message.ActionID];
  if (typeof cb === 'function') {
    if (message.Response !== 'Success') {
      return cb("Origination Failed: " + message.Reason, message);
    }
    return cb(null, message);
  }
};

module.exports = {
  Connection: Connection
};
