# Description:
#   Shows what's edible.
#
# Notes:
#   This includes
#    * fetching from fabrik
#    * fetching from flexibelpoint
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
  fp : "Flexibelpoint"
  er : "Erni's [sic]"
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
    docDate = $("#special-modal h3:eq(0)").text()
    /(\d{2}\.\d{2}\.\d{4}) bis (\d{2}\.\d{2}\.\d{4})/.exec(docDate)

  extractMeal: ($, day) ->
    menu = $("#special-modal tr:eq(#{day + 2}) td:eq(1)").text()
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

class Flexibelpoint
  target : "http://flexibelpoint.at"
  errors :
    closed : "flexibelpoint is closed"

  constructor: (@robot) ->

  extractWeeklyMeal: ($) ->
    $.trim($(".menuday:eq(0)").next().text())

  extractMeal: ($, day) ->
    $.trim($(".menuday:eq(#{day})").next().text())

  getMenu: (now, day) =>
    lastCheck = moment(@robot.brain.get("feedme.flexibelpoint.lastCheck") or 0)
    # only check once per day, otherwise we're good to go
    return if now.isSameOrBefore(lastCheck, 'day')

    rawbody = fetch(@target)

    # hack to include jQuery
    $ = require("jquery")(jsdom.jsdom(rawbody).defaultView)

    # flexibelpoint is closed
    if day > 5
      @robot.brain.set "feedme.flexibelpoint.save", @errors.closed

    else
      @robot.brain.set "feedme.flexibelpoint.save", @extractMeal($, day) + "\n" +  "Wochenempfehlung: " + @extractWeeklyMeal($)
      @robot.brain.set "feedme.flexibelpoint.lastCheck", now

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
  flexibelpoint = new Flexibelpoint(robot)
  ernis = new Ernis(robot)


  robot.respond /feedme/i, (res) ->
    now = moment()
    # ranging from 1 (Monday) to 7 (Sunday)
    day = now.isoWeekday()
    fabrik.getMenu(now, day)
    flexibelpoint.getMenu(now, day)
    ernis.getMenu(now, day)
    fabrikMenu = robot.brain.get "feedme.fabrik.save"
    flexibelpointMenu = robot.brain.get "feedme.flexibelpoint.save"
    ernisMenu = robot.brain.get "feedme.ernis.save"

    res.send "Heutiges Mittagsmenü:\n
      \nFabrik: \n#{fabrikMenu}\n
      \nFlexibelpoint: \n#{flexibelpointMenu}\n
      \nErni's [sic]: \n#{ernisMenu}\n
      \nNatürlich gibt es auch noch:
      \nSpar, Billa, Burgerking, Gumpendorfer, Margaretengürtel oder Pizza."

