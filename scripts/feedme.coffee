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
require "datejs"

DAY = 1000 * 60 * 60  * 24

getDateDiff = (date1, date2, interval) ->
  Math.round((date1.getTime() - date2.getTime()) / interval)

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

  getMenu: () =>
    now = new Date()
    day = now.getDay()
    lastCheck = new Date(@robot.brain.get("feedme.fabrik.lastCheck") or 0)
    # only check once per day, otherwise we're good to go
    return if getDateDiff(now, lastCheck, DAY) < 0

    @robot.brain.set "feedme.fabrik.lastCheck", now
    rawbody = fetch(@target)

    if @checkHoliday(rawbody.toString())
      @robot.brain.set "feedme.fabrik.save", @errors.holiday
      return

    # hack to include jQuery
    $ = require("jquery")(jsdom.jsdom(rawbody).defaultView)
    parsedDates = @parseDates($)

    # check for outdated menu
    if now.getTime() > (Date.parseExact(parsedDates[2], "d.M.yyyy").getTime() + DAY)
      @robot.brain.set "feedme.fabrik.save", @errors.menuFromPast
      return

    # check for future menu
    if now.getTime() < Date.parseExact(parsedDates[1], "d.M.yyyy").getTime()
      @robot.brain.set "feedme.fabrik.save", @errors.menuFromFuture
      return

    if day == 5 or day == 6
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

  getMenu: () =>
    now = new Date()
    day = now.getDay()

    lastCheck = new Date(@robot.brain.get("feedme.ernis.lastCheck") or 0)
    # only check once per day, otherwise we're good to go
    return if getDateDiff(now, lastCheck, DAY) < 0

    @robot.brain.set "feedme.ernis.lastCheck", now
    rawbody = fetch(@target)

    # hack to include jQuery
    $ = require("jquery")(jsdom.jsdom(rawbody).defaultView)
    # ernis closed
    if day == 5 or day == 6
      @robot.brain.set "feedme.ernis.save", @errors.closed
      return

    @robot.brain.set "feedme.ernis.save", @extractMeal($, day)


module.exports = (robot) ->

  fabrik = new Fabrik(robot)
  ernis = new Ernis(robot)
  robot.respond /feedme/i, (res) ->
    fabrik.getMenu()
    ernis.getMenu()
    fabrikMenu = robot.brain.get "feedme.fabrik.save"
    ernisMenu = robot.brain.get "feedme.ernis.save"
    res.send "Heutiges Mittagsmenü: \nFabrik: \n#{fabrikMenu}\n\nErni's: \n#{ernisMenu}"
