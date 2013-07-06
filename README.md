node-asterisk-ami
=================

Asterisk AMI library for NodeJS

Inspired by:
* [holidayextras/node-asterisk-ami](https://github.com/holidayextras/node-asterisk-ami)
* [englercj/node-esl](https://github.com/englercj/node-esl)

Features
--------

* AMI-JS parsing:
   * All AMI messages are parsed and objectified
   * AMI messages which have duplicate keys will automatically be converted to Arrays
   * Arrays provided to AMI calls will automatically be converted to multiple keys
* Two-level callback tracking and queuing:
   * All Actions are submitted asynchronously to Asterisk
   * Any callbacks provided treated as "ACK" callbacks; they are executed when the associated "Response" event is received
   * Originate actions are always asynchronously called, but there is a 'sync' option which can be passed to only call the callback when the OriginateResponse is received.
   * Orignate also allows a 'complete' property to be supplied, which will be executed only when the OriginateResponse is received.
   * AsyncAGI also has two callbacks: for ACK and for completion:
      * The method callback, if it exists, will be called when Asterisk queues the AGI command.
      * The `complete` property will be executed when the AGI command has been executed (on the `Exec` SubEvent)
* Regardless of any special handling above, all AMI messages will be emitted as `message` events on the `Connection` object

Basic Usage
-----------

```Javascript
var AMI = require('node-asterisk-ami');
var amiconn = new AMI.Connection({
   username: 'MyUserName',
   password: 'MySecretPassword'
});
amiconn.on('ready',function(){
   amiconn.originate({
      Channel: 'SIP/testme',
      Application: 'AGI',
      Data: 'agi:async',
      complete: function(message){
         if(message.Response == 'Success') {
            console.log("Call is connected");
         } else {
            console.log("Call failed: "+ message.Reason);
         }
      }
   },function(){
      console.log("Originate command received");
   });
});
```

AMI.Connection `AMI.Connection(options,[callback])`
===================================================

Available `options`:
* host: hostname or IP address of Asterisk server (default: 'localhost')
* port: AMI port of Asterisk server (default: 5038)
* username:  Asterisk AMI username
* password:  Asterisk AMI secret
* debug: (boolean) Increase logging level (default: false)
* events: (boolean) Listen for AMI events (default: true)

If provided, the callback will be called when Asterisk reports the connection to be ready

Methods:

send `AMI.Connection.send(command)`
-----------------------------------

Low-level method to send AMI commands directly.  If `command` is a string, no processing will be performed before sending the command to Asterisk.  If `command` is an object, it will be parsed into an AMI-compatable Action before sending.

Note that using `send` directly will bypass all tracking and queuing.  It is up to you to add ActionIDs and CommandIDs as appropriate.

action `AMI.Connection.action(action,[args],[cb])`
------

Send an arbitrary AMI Action to Asterisk.

`action` may be a string or an object.  A string will be used as the value for the `Action` key.  An object is presumed to contain a set of properties which will be converted to key-value pairs for AMI.

`args`, if present, should be an object which will be appended to the `action` object.

`cb`, if present, will be called when Asterisk acknowledges receipt of the Action.

Note that this method will not automatically track Originate and AGI execution.  Please use the `originate` or `agi` methods for that.

originate `AMI.Connection.originate(args,[cb])`
---------

Send and track an `Originate` AMI action to Asterisk.

Available additional options (include in the `args` object):
* sync:  (boolean, false) Execute `cb` only on *completion* of the Originate command, rather than acceptance
* complete: (function) Executed on *completion* of the Originate command

agi `AMI.Connection.agi(command,[args],[cb])`
-----

Send and track an AsyncAGI command to Asterisk.

`command` may be a string or an object.  Strings will be used as the value for the `Command` AMI key.

`args`, if present, should be an object which will be appended to the action (not the command; append to `command` any arguments required for that command)

`cb`, if present, will be called when Asterisk acknowledges receipt of the Action.

Events
======

Each of the events are passed with the full, objectified AMI message

* `message`: Emitted on each AMI message

* `response:<ActionID>`: Emitted when an AMI response with an associated ActionID is received

* `event:<ActionID>`: Emitted when an AMI event with an associated ActionID is received

* `originate:<ActionID>`: Emitted when an AMI OriginateReponse event with an associated ActionID is received

* `agi:exec:<CommandID>`: Emitted when an AGI Exec event with an associated CommandID is received

* `agi:start`: Emitted when a new AsyncAGI session is started.  The usual AGI variables will be parsed into an object as the `Env` property of the object passed with this event.

* `agi:end`: Emitted when a new AsyncAGI session is started.

For more interpreted events, you may also listen on `AGI.Connection.parser` for these additional events:
* `ami:event` - All AMI Events (message contains an `Event` key)
* `ami:response` - All AMI Response messages (message contains an `Response` key)
* `ami:originate` - All AMI Originate Reponse messages (message contains an `OriginateResponse` key)
* `ami:agi` - All AsyncAGI events
* `ami:agi:start` - All AsyncAGI events with SubEvent 'Start'
* `ami:agi:end` - All AsyncAGI events with SubEvent 'End'
* `ami:agi:command:start` - All AsyncAGI event, SubEvent 'Start' which refer to an AGI Command
* `ami:agi:command:end` - All AsyncAGI event, SubEvent 'End' which refer to an AGI Command
* `ami:agi:session:start` - All AsyncAGI event, SubEvent 'Start' which refer to an AGI Session (Env will be parsed to an object as property Env)
* `ami:agi:session:end` - All AsyncAGI event, SubEvent 'End' which refer to an AGI Session
