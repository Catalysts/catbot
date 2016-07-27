# Description:
#   Shows what"s edible.
#
# Notes:
#   This includes
#    * fetching from fabrik
#    * fetching from ernis
#
# Author: cholter

urllib = require "urllib-sync"
jsdom = require "jsdom"
moment = require "moment-timezone"

FOOD_TIME =
  HOUR : 11
  MINUTE : 45
  OFFSET : moment().tz('Europe/Vienna').utcOffset()*60

FOOD_CHANNEL = "vie-food"

FOOD_REGEX = "fab?r?i?k?|ern?i?s?|spa?r?|bil?l?a?|bur?g?e?r?k?i?n?g?|bk|gum?p?e?n?d?o?r?f?e?r?|mar?g?a?r?e?t?e?n?g?ü?r?t?e?l?|piz?z?a?"

FOODTYPES =
  fa : "Fabrik"
  er : "Erni's"
  sp : "Spar"
  bi : "Billa"
  bu : "Burger King"
  gu : "Gumpendorfer"
  ma : "Margaretengürtel"
  pi : "Pizza"

fetch = (target) ->
  urllib.request(target).data

class Fabrik
  target : "http://diefabrik.co.at"
  errors :
    closed : "fabrik is closed"
    menuFromPast : "the menu is outdated"
    menuFromFuture : "the menu is from the future"
    resting : "fabrik is on a day off"

  constructor: (@robot) ->

  parseDates: ($) ->
    docDate = $("#menu11 h4:eq(1)").html()
    /(\d{2}\.\d{2}\.\d{4}) bis (\d{2}\.\d{2}\.\d{4})/.exec(docDate)

  extractMeal: ($, day) ->
    menu = $("#menu11 tr:eq(#{day + 1}) td:eq(1)").text()
    # Ruhetag
    if menu.toLowerCase() is 'ruhetag' then @errors.resting else menu

  getMenu: (now, day) =>
    lastCheck = moment(@robot.brain.get("feedme.fabrik.lastCheck") or 0)
    # only check once per day, otherwise we're good to go
    return if now.isSameOrBefore(lastCheck, 'day')

    rawbody = fetch(@target)

    # hack to include jQuery
    $ = require("jquery")(jsdom.jsdom(rawbody).defaultView)
    parsedDates = @parseDates($)

    # fabrik is closed
    if day > 5
      @robot.brain.set "feedme.fabrik.save", @errors.closed

    # check for outdated menu
    else if now.isAfter(moment(parsedDates[2], "DD.MM.YYYY"), 'day')
      @robot.brain.set "feedme.fabrik.save", @errors.menuFromPast

    # check for future menu
    else if now.isBefore(moment(parsedDates[1], "DD.MM.YYYY"), 'day')
      @robot.brain.set "feedme.fabrik.save", @errors.menuFromFuture

    else
      @robot.brain.set "feedme.fabrik.save", @extractMeal($, day)
      @robot.brain.set "feedme.fabrik.lastCheck", now

class Ernis
  target : "http://www.ernis.at"
  errors :
    closed : "ernis is closed"

  constructor: (@robot) ->

  extractMeal: ($, day) ->
    $("#accordion > div .moduletable:eq(#{day-1}) > div").text().trim()

  getMenu: (now, day) =>
    lastCheck = moment(@robot.brain.get("feedme.ernis.lastCheck") or 0)
    # only check once per day, otherwise we're good to go
    return if now.isSameOrBefore(lastCheck, 'day')

    rawbody = fetch(@target)

    # hack to include jQuery
    $ = require("jquery")(jsdom.jsdom(rawbody).defaultView)
    # erni's is closed
    if day > 5
      @robot.brain.set "feedme.ernis.save", @errors.closed

    else
      @robot.brain.set "feedme.ernis.save", @extractMeal($, day)
      @robot.brain.set "feedme.ernis.lastCheck", now


module.exports = (robot) ->

  fabrik = new Fabrik(robot)
  ernis = new Ernis(robot)

  # note that we can't store the reminders anywhere because node.js returns a
  # Timeout object in contrast to the usual (browser) integer which is then
  # needed to clear the timeout later on (if there is a new reminder set). This
  # Timeout object can't be JSON.stringified (circular reference) and thus not
  # stored. As a result reminders are lost on restart of hubot.
  reminder = {}

  # wait for given time and then send a message to FOOD_CHANNEL with all
  # subscribed users for this food type.
  setReminder = (foodType, hour = FOOD_TIME.HOUR, minute = FOOD_TIME.MINUTE, offset = FOOD_TIME.OFFSET ) ->
    setTimeout ( =>
      eater = robot.brain.get "feedme.eater"
      people = if eater and foodType of eater then eater[foodType] else []
      msg = if people.length > 0 then "#{people.join(", ")}:\n" else ""
      robot.messageRoom FOOD_CHANNEL, msg + "Los los ... #{FOODTYPES[foodType]} wartet nicht!"
      delete reminder[foodType]
      # clear all eaters, they're supposed to be fed.
      if eater then delete eater[foodType]
      robot.brain.set "feedme.eater", eater
    ), moment().hour(hour).minute(minute).seconds(0)
      .diff(moment(), 'milliseconds') - offset*1000

  existsReminder = (foodType) ->
    foodType of reminder

  # clear all reservations + reminders @midnight
  setClearTimeout = ->
    setTimeout ( =>
      robot.brain.set "feedme.eater", {}
      reminder = {}
      setClearTimeout()
    ), moment().endOf('day').diff(moment(), 'milliseconds')

  setClearTimeout()

  robot.respond /feedme/i, (res) ->
    now = moment()
    # ranging from 1 (Monday) to 7 (Sunday)
    day = now.isoWeekday()
    fabrik.getMenu(now, day)
    ernis.getMenu(now, day)
    fabrikMenu = robot.brain.get "feedme.fabrik.save"
    ernisMenu = robot.brain.get "feedme.ernis.save"

    res.send "Heutiges Mittagsmenü:\n
      \nFabrik: \n#{fabrikMenu}\n
      \nErni's: \n#{ernisMenu}\n
      \nNatürlich gibt es auch noch:
      \nSpar, Billa, Burgerking, Gumpendorfer, Margaretengürtel oder Pizza."

  # subscribe to food and reminder
  robot.hear (new RegExp("(#{FOOD_REGEX}) \\+(\\d*)", "i"))
  , (res) ->
    foodType = res.match[1].toLowerCase().substr(0,2)
    if foodType is "bk" then foodType = "bu"
    eater = robot.brain.get("feedme.eater") or {}
    unless foodType of eater then eater[foodType] = []
    # save name of user who sent the message to notify him later
    count = res.match[2]
    user = "@#{res.message.user.name}"
    user += " x#{count}" if count > 1
    eater[foodType].push user
    robot.brain.set "feedme.eater", eater
    # seconds after UTC (CEST = 7200)
    offset = res.message.user.slack.tz_offset
    # if there is no reminder + it's before default time => set new reminder
    if moment().isBefore(moment().hour(FOOD_TIME.HOUR).minute(FOOD_TIME.MINUTE).subtract(offset, 's'))
      unless existsReminder(foodType)
        reminder[foodType] = setReminder(foodType)

  # clears old reminder + sets new one with given time.
  robot.hear (new RegExp("(#{FOOD_REGEX}) (\\d\\d).?(\\d\\d)", "i"))
  , (res) ->
    foodType = res.match[1].toLowerCase().substr(0,2)
    if foodType is "bk" then foodType = "bu"
    hour = res.match[2]
    minute = res.match[3]
    # seconds after UTC (CEST = 7200)
    offset = res.message.user.slack.tz_offset
    if foodType of reminder
      clearTimeout(reminder[foodType])
    reminder[foodType] = setReminder(foodType, hour, minute, offset)

  # clears old reminder + reminds everybody to go to lunch.
  robot.hear (new RegExp("(#{FOOD_REGEX}) now", "i"))
  , (res) ->
    foodType = res.match[1].toLowerCase().substr(0,2)
    if foodType is "bk" then foodType = "bu"
    if foodType of reminder
      clearTimeout(reminder[foodType])
    reminder[foodType] = setReminder(foodType, 0, 0, 0)
