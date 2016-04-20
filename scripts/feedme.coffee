# Description:
#   Shows what"s edible.
#
# Notes:
#   This includes
#    * fetching from fabrik
#    * fetching from ernis

urllib = require "urllib-sync"
jsdom = require "jsdom"
require "datejs"

DAY = 1000 * 60 * 60  * 24

getDateDiff = (date1, date2, interval) ->
  return Math.round((date1.getTime() - date2.getTime()) / interval)

class Fabrik
  target : "http://www.diefabrik.co.at/mittagsmenue/index.html"
  holidayMagic : "urlaub"
  errors:
	  closed : "fabrik is closed"
	  menuFromPast :"the menu is outdated"
	  menuFromFuture :"the menu is from the future"
	  resting :"fabrik is on a day off"
	  holiday :"fabrik is probably on holiday, fall back to manual check"

  constructor: (@robot) ->

  fetch: =>
    return urllib.request(@target).data

  checkHoliday: (text) =>
    return true if text.toLowerCase().indexOf(@holidayMagic) > 0

  parseDates: ($) ->
    docDate = $("h2:eq(0)").html()
    return /(\d{2}\.\d{2}\.\d{4}) bis (\d{2}\.\d{2}\.\d{4})/.exec(docDate)

  extractMeal: ($) ->
    # weekday: 0 Sunday to 6 Saturday
    day = new Date().getDay()

    # Saturday & Sunday
    return @errors.closed if day == 6 | day == 0
    menu = $(".contenttable .tr-#{(day-1)*2} .td-2").html()
    # Ruhetag
    return @errors.resting if menu.toLowerCase() == 'ruhetag'
    # all good :)
    return menu

  getMenue: () =>
    now = new Date()
    lastCheck = new Date(@robot.brain.get "feedme.fabrik.lastCheck")
    lastCheck = Date.parseExact("01.01.1970", "d.M.yyyy") if not lastCheck
    # only check once per day, otherwise we're good to go
    if getDateDiff(now, lastCheck, DAY) > 0
      rawbody = @fetch()

      return @errors.holiday if @checkHoliday(rawbody.toString())

      # hack to include jQuery
      $ = require("jquery")(jsdom.jsdom(rawbody).defaultView)
      parsedDates = @parseDates($)

      # check for outdated menue
      if now.getTime() > (Date.parseExact(parsedDates[2], "d.M.yyyy").getTime() + DAY)
        @robot.brain.set "feedme.fabrik.save", @errors.menuFromPast

      # check for future menue
      else if now.getTime() < Date.parseExact(parsedDates[1], "d.M.yyyy").getTime()
        @robot.brain.set "feedme.fabrik.save", @errors.menuFromFuture

      else
        @robot.brain.set "feedme.fabrik.save", @extractMeal($)

      @robot.brain.set "feedme.fabrik.lastCheck", now

module.exports = (robot) ->

  fabrik = new Fabrik(robot)
  robot.respond /feedme/i, (res) ->
    fabrik.getMenue()
    fabrikMenue = robot.brain.get "feedme.fabrik.save"
    res.send "Heutiges Mittagsmenü: \nFabrik: \n\t#{fabrikMenue}"
