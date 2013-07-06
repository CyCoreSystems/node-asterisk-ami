var Parser, events, util;

events = require('events');

util = require('util');

Parser = function(socket) {
  events.EventEmitter.call(this);
  if (!socket) {
    return this.emit('error', 'No socket passed to Parser');
  }
  this.socket = socket;
  this.socket.setEncoding('ascii');
  this.buffer = '';
  this.lines = [];
  this.initialized = false;
  this.separator = "\r\n";
  this.socket.on('data', this._onData.bind(this));
  this.socket.on('end', this._onEnd.bind(this));
  this.on('line', this._onLine.bind(this));
  this.on('message', this._onMessage.bind(this));
};

util.inherits(Parser, events.EventEmitter);

Parser.prototype.flush = function() {
  this.buffer = '';
  return this.lines = [];
};

Parser.prototype._onEnd = function() {};

Parser.prototype._onData = function(data) {
  var lines, self;
  self = this;
  this.buffer += data;
  lines = data.split(this.separator);
  lines[0] = this.buffer + lines[0];
  this.buffer = lines.pop();
  lines.forEach(function(line) {
    return self.emit('line', line);
  });
};

Parser.prototype._onLine = function(line) {
  if (!this.initialized) {
    this.initialized = 'true';
    this.emit('ami:ready');
    return;
  }
  if (!line) {
    this.emit('message', this.lines.slice(0));
    this.lines = [];
  }
  this.lines.push(line);
};

Parser.prototype._onMessage = function(lines) {
  var message;
  if (!lines) {
    return;
  }
  message = this.parse(lines);
  if (!Object.keys(message).length) {
    return;
  }
  this.emit('ami:message', message);
  if (message.Response) {
    this.emit('ami:response', message);
  }
  if (message.Event) {
    this.emit('ami:event', message);
    if (message.Event === 'AsyncAGI') {
      if (message.SubEvent === 'Start') {
        this.emit('ami:agi:start', message);
        this._onAGIStart(message);
      }
      if (message.SubEvent === 'End') {
        this.emit('ami:agi:end', message);
        this._onAGIEnd(message);
      }
      if (message.SubEvent === 'Exec') {
        this.emit('ami:agi:exec', message);
      }
    }
    if (message.Event === 'OriginateResponse') {
      this.emit('ami:originate', message);
    }
  }
};

Parser.prototype._onAGIStart = function(message) {
  if (message.Command) {
    return this.emit('ami:agi:command:start', message);
  }
  message.Env = this.parseEnv(message.Env);
  return this.emit('ami:agi:session:start', message);
};

Parser.prototype._onAGIEnd = function(message) {
  if (message.Command) {
    return this.emit('ami:agi:command:end', message);
  }
  return this.emit('ami:agi:session:end', message);
};

Parser.prototype.parse = Parser.prototype.toObj = function(lines) {
  var msg;
  msg = {};
  lines.forEach(function(line) {
    var key, tmp, val;
    tmp = line.split(':');
    if (tmp.length < 2) {
      return;
    }
    key = tmp.shift();
    val = tmp.join(':');
    if (msg[key]) {
      if (typeof msg[key] === 'array') {
        return msg[key].push(val.trim());
      } else {
        return msg[key] = [msg[key], val.trim()];
      }
    } else {
      return msg[key] = val.trim();
    }
  });
  return msg;
};

Parser.prototype.toAMI = function(obj) {
  var lines, self;
  self = this;
  lines = [];
  obj.forEach(function(val, key) {
    if (typeof val === 'string') {
      return lines.push([key, val].join(': '));
    } else if (typeof val === 'array') {
      val.forEach(function(item) {
        return lines.push([key, item].join(': '));
      });
    } else {
      self.emit('error', "Unhandled type in toAMI:" + typeof val);
      return;
    }
  });
  return lines.join(this.separator).concat(this.separator);
};

Parser.prototype.parseEnv = function(env) {
  var lines, ret;
  ret = {};
  lines = env.split('%0A');
  _.each(lines, function(line) {
    var pieces;
    pieces = line.split('%3A%20');
    return ret[pieces[0]] = pieces[1];
  });
  return ret;
};

module.exports = {
  Parser: Parser
};
