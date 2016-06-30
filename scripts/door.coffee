# A script that registers a handler to receive HTTP POST
# requests at /vie/door. These requests are sent by the
# office infrastructure and contain information about the
# person that opens the door. This is then posted to our
# office channel.
module.exports = (robot) ->
  robot.router.post '/vie/door', (req, res) ->
    req = JSON.parse(req)
    return unless req?.firstName and req?.lastName
    robot.messageRoom '#vie', "#{req.firstName + req.lastName} entered the office!"
