node-asterisk-ami
=================

Asterisk AMI library for NodeJS

Based off of:
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
      Channel: 'SIP/testme'
      Application: 'AGI'
      Data: 'agi:async'
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

