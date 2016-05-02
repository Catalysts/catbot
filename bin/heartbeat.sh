#!/bin/bash
[ $(TZ=Europe/Vienna date +'%H') -lt 6 ] || curl -v "https://catalysts-hubot.herokuapp.com/heartbeat"
