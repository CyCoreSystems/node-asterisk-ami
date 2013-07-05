bunyan = require 'bunyan'

Logger = {}

amiRequest = (req)->
  if not req
    return {}
  return req

amiResponse = (res)->
  if not res
    return {}
  return res

# Serializers for AMI requests, responses
Logger.serializers =
  req: amiRequest
  res: amiResponse

# Default Logger simply uses console.* methods
Logger.createLogger = (debug)->
  if debug
    return bunyan.createLogger {
      name: "AMI"
      serializers: Logger.serializers
      streams: [
        {
          level: 'trace'
          stream: process.stdout
        }
      ]
    }
  return bunyan.createLogger {
    name: "AMI"
    serializers: Logger.serializers
    streams: [
      {
        level: 'warn'
        stream: process.stderr
      }
    ]
  }

module.exports = Logger
