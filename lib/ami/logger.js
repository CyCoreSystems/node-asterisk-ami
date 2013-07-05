var Logger, amiRequest, amiResponse, bunyan;

bunyan = require('bunyan');

Logger = {};

amiRequest = function(req) {
  if (!req) {
    return {};
  }
  return req;
};

amiResponse = function(res) {
  if (!res) {
    return {};
  }
  return res;
};

Logger.serializers = {
  req: amiRequest,
  res: amiResponse
};

Logger.createLogger = function(debug) {
  if (debug) {
    return bunyan.createLogger({
      name: "AMI",
      serializers: Logger.serializers,
      streams: [
        {
          level: 'trace',
          stream: process.stdout
        }
      ]
    });
  }
  return bunyan.createLogger({
    name: "AMI",
    serializers: Logger.serializers,
    streams: [
      {
        level: 'warn',
        stream: process.stderr
      }
    ]
  });
};

module.exports = Logger;
