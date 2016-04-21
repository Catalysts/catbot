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
moment = require "moment"


fetch = (target) ->
  urllib.request(target).data


class Fabrik
  target : "http://www.diefabrik.co.at/mittagsmenue/index.html"
  holidayMagic : "urlaub"
  errors :
    closed : "fabrik is closed"
    menuFromPast : "the menu is outdated"
    menuFromFuture : "the menu is from the future"
    resting : "fabrik is on a day off"
    holiday : "fabrik is probably on holiday, fall back to manual check"

  constructor: (@robot) ->

  checkHoliday: (text) =>
    text.toLowerCase().indexOf(@holidayMagic) > 0

  parseDates: ($) ->
    docDate = $("h2:eq(0)").html()
    /(\d{2}\.\d{2}\.\d{4}) bis (\d{2}\.\d{2}\.\d{4})/.exec(docDate)

  extractMeal: ($, day) ->
    menu = $(".contenttable .tr-#{(day-1)*2} .td-2").html()
    # Ruhetag
    if menu.toLowerCase() is 'ruhetag' then @errors.resting else menu

  getMenu: (now, day) =>
    lastCheck = moment(@robot.brain.get("feedme.fabrik.lastCheck") or 0)
    # only check once per day, otherwise we're good to go
    return if now.isSameOrBefore(lastCheck, 'day')

    @robot.brain.set "feedme.fabrik.lastCheck", now
    rawbody = fetch(@target)

    if @checkHoliday(rawbody.toString())
      @robot.brain.set "feedme.fabrik.save", @errors.holiday
      return

    # hack to include jQuery
    $ = require("jquery")(jsdom.jsdom(rawbody).defaultView)
    parsedDates = @parseDates($)

    # check for outdated menu
    if now.isAfter(moment(parsedDates[2], "DD.MM.YYYY"), 'day')
      @robot.brain.set "feedme.fabrik.save", @errors.menuFromPast
      return

    # check for future menu
    if now.isBefore(moment(parsedDates[1], "DD.MM.YYYY"), 'day')
      @robot.brain.set "feedme.fabrik.save", @errors.menuFromFuture
      return

    # fabrik is closed
    if day > 5
      @robot.brain.set "feedme.fabrik.save", @errors.closed
      return

    @robot.brain.set "feedme.fabrik.save", @extractMeal($, day)

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

    @robot.brain.set "feedme.ernis.lastCheck", now
    rawbody = fetch(@target)

    # hack to include jQuery
    $ = require("jquery")(jsdom.jsdom(rawbody).defaultView)
    # erni's is closed
    if day > 5
      @robot.brain.set "feedme.ernis.save", @errors.closed
      return

    @robot.brain.set "feedme.ernis.save", @extractMeal($, day)


module.exports = (robot) ->

  fabrik = new Fabrik(robot)
  ernis = new Ernis(robot)
  now = moment()
  # ranging from 1 (Monday) to 7 (Sunday)
  day = now.isoWeekday()

  robot.respond /feedme/i, (res) ->
    fabrik.getMenu(now, day)
    ernis.getMenu(now, day)
    fabrikMenu = robot.brain.get "feedme.fabrik.save"
    ernisMenu = robot.brain.get "feedme.ernis.save"
    res.send "Heutiges Mittagsmenü:\n
      \nFabrik: \n#{fabrikMenu}\n
      \nErni's: \n#{ernisMenu}"
