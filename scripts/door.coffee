# A script that registers a handler to receive HTTP POST
# requests at /vie/door. These requests are sent by the
# office infrastructure and contain information about the
# person that opens the door. This is then posted to our
# office channel.
module.exports = (robot) ->
  robot.router.post '/vie/door', (req, res) ->
    unless req.body?.firstName and req.body?.lastName
      res.status 400
      res.send 'Rad Request'
      return

    robot.messageRoom 'vie', "#{req.body.firstName + " " + req.body.lastName} entered the office!"
    res.send 'OK'
