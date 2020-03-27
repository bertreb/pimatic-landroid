module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  http = require('http')
  fs = require('fs')
  path = require('path')
  _ = require('lodash')
  M = env.matcher
  Moment = require('moment')
  LandroidCloud = require('./api.js')
  LandroidDataset = require('./LandroidDataset.js')

  class LandroidPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-landroid-config-schema'
      @configProperties = pluginConfigDef.properties

      deviceConfigDef = require("./device-config-schema")

      @email = @config.email
      @password = @config.password
      @landroidCloud = new LandroidCloud(@email, @password, {"log": env.logger})

      @framework.deviceManager.registerDeviceClass('LandroidMower', {
        configDef: deviceConfigDef.LandroidMower,
        createCallback: (config, lastState) => new LandroidMower(config, lastState, @framework, @)
      })

      @framework.ruleManager.addActionProvider(new LandroidActionProvider(@framework))

      @framework.deviceManager.on('discover', (eventData) =>
        @framework.deviceManager.discoverMessage 'pimatic-landoid', 'Searching for new devices'

        @landroidCloud.getUserDevices()
        .then((devices)=>
          for device in devices
            env.logger.info "found device: " + JSON.stringify(device,null,2)
            if not inConfig(device.serial_number, "LandroidMower")
              config =
                id: "landroid_" + device.serial_number
                name: "Landroid " + device.name # + device.product_id
                class: "LandroidMower"
                serial: device.serial_number
                mac: device.mac_address
                landroid_id: device.id
                product_id: device.product_id
                command_in: device.mqtt_topics.command_in
                command_out: device.mqtt_topics.command_out
              @framework.deviceManager.discoveredDevice( "pimatic-sounds", config.name, config)
        )
        .catch((err)=>
          env.logger.debug "Error in discover getUserDevices " + err
        )
      )

      inConfig = (device_serial, cn) =>
        for device in @framework.deviceManager.devicesConfig
          if device.class is cn
            if (device.serial).indexOf(String device_serial) >= 0
              return true
        return false


  class LandroidMower extends env.devices.Device

    constructor: (@config, lastState, @framework, @plugin) ->
      @id = @config.id
      @name = @config.name
      @serial = @config.serial
      @mowerOnline = false
      @schedule = []
      @emptySchedule = []

      for x in [1..7]
        @emptySchedule.push ["9:00",0,0] 
      @daysOfWeek =
        sunday: 0
        monday: 1
        tuesday: 2
        wednesday: 3
        thursday: 4
        friday: 5
        saturday: 6
  
      if @_destroyed then return
      #
      # Configure attributes
      #

      @attributes = {
        cloud:
          description: "If plugin is connected to the Worx-landroid cloud"
          type: "string"
          acronym: "cloud"
        status:
          description: "Actual status of the mower"
          type: "string"
          acronym: "status"
        mower:
          description: "Showing if mower is off or online"
          type: "string"
          acronym: "mower"
        rainDelay:
          description: "The delay after rain, before mowing"
          type: "number"
          acronym: "rainDelay"
          unit: "min"
        totalTime:
          description: "The totalTime the mower has mowed"
          type: "number"
          acronym: "totalTime"
          unit: "min"
        totalDistance:
          description: "The totalDistance the mower has mowed"
          type: "number"
          acronym: "totalDistance"
          unit: "m"
        totalBladeTime:
          description: "The totalBladeTime the mower has mowed"
          type: "number"
          acronym: "totalBladeTime"
          unit: "min"
        battery:
          description: "Battery",
          type: "number"
          displaySparkline: false
          unit: "%"
          icon:
            noText: false
            mapping: {
              'icon-battery-empty': 0
              'icon-battery-fuel-1': [0, 20]
              'icon-battery-fuel-2': [20, 40]
              'icon-battery-fuel-3': [40, 60]
              'icon-battery-fuel-4': [60, 80]
              'icon-battery-fuel-5': [80, 100]
              'icon-battery-filled': 100
            }
        batteryCharging:
          description: "If true battery is charging"
          type: "boolean"
          acronym: "batteryCharging"
        batteryTemperature:
          description: "Battery temperature of mower"
          type: "number"
          unit: "°C"
          acronym: "batteryTemperature"
        wifi:
          description: "Wifi strenght at the mower"
          type: "number"
          unit: "dBm"
          acronym: "wifi"
        nextMowe:
          description: "Next scheduled mowing"
          type: "string"
          acronym: "nextMowe"
      }


      @attributeValues = {}
      @attributeValues.cloud = lastState?.cloud?.value or "disconnected"
      @attributeValues.status = lastState?.status?.value or "idle"
      @attributeValues.mower = lastState?.mower?.value or "offline"
      @attributeValues.rainDelay = lastState?.rainDelay?.value or 0
      @attributeValues.totalTime = lastState?.totalTime?.value or 0
      @attributeValues.totalDistance = lastState?.totalDistance?.value or 0
      @attributeValues.totalBladeTime = lastState?.totalBladeTime?.value or 0
      @attributeValues.battery = lastState?.battery?.value or 0
      @attributeValues.batteryCharging = lastState?.batteryCharging?.value or false
      @attributeValues.batteryTemperature = lastState?.batteryTemperature?.value or 0.0
      @attributeValues.wifi = lastState?.wifi?.value or 0
      @attributeValues.nextMowe = lastState?.nextMowe?.value or ""

      for key,attribute of @attributes
        do (key) =>
          @_createGetter key, () =>
            return Promise.resolve @attributeValues[key]
          @setAttr(key, @attributeValues[key])

      @framework.on "after init", =>
        @setAttr("cloud","disconnected")
        @setAttr("mower","offline")

      @plugin.landroidCloud.on "mqtt", (mower, data)=>
        @processMowerMessage(mower)
        @processMowerMessage(data)

      @plugin.landroidCloud.on "online",  (msg)=>
        env.logger.debug "online message received processing " + JSON.stringify(msg,null,2)
        @processMowerMessage(msg)
      @plugin.landroidCloud.on "offline",  (msg)=>
        env.logger.debug "offline message received processing"+ JSON.stringify(msg,null,2)
        @processMowerMessage(msg)

      @plugin.landroidCloud.on "connect",  (data)=>
        @setAttr("cloud","connected")

      super()

    processMowerMessage: (data) =>
      #env.logger.debug "processMowerMessage data: " + JSON.stringify(data,null,2)
      if data?
        if data.online?
          if data.online 
            @setAttr("mower", "online")
            @mowerOnline = true
          else
            @setAttr("mower","offline")
            @mowerOnline = false
        landroidDataset = new LandroidDataset(data)
        if landroidDataset.statusDescription?
          @setAttr("status",landroidDataset.statusDescription)

        if landroidDataset.rainDelay?
          @setAttr("rainDelay",landroidDataset.rainDelay)
        ###
        if landroidDataset.language?
          @setAttr("language",landroidDataset.language)
        ###
        if landroidDataset.batteryLevel?
          @setAttr("battery",landroidDataset.batteryLevel)
        if landroidDataset.batteryTemperature?
          @setAttr("batteryTemperature",landroidDataset.batteryTemperature)
        if landroidDataset.batteryCharging?
          @setAttr("batteryCharging",landroidDataset.batteryCharging)
        if landroidDataset.wifiQuality?
          @setAttr("wifi",landroidDataset.wifiQuality)
        if landroidDataset.totalTime?
          @setAttr("totalTime",landroidDataset.totalTime)
        if landroidDataset.totalDistance?
          @setAttr("totalDistance",landroidDataset.totalDistance / 100)
        if landroidDataset.totalBladeTime?
          @setAttr("totalBladeTime",landroidDataset.totalBladeTime)
        if landroidDataset.schedule?
          @schedule = landroidDataset.schedule
          @setSchedule(landroidDataset.schedule)
          env.logger.debug "mqtt schedule received"


    checkAndCompleteSchedule: (scheduleIn) =>
      try
        result =
          schedule: @emptySchedule
          error: true
          reason: "no reason"
        days = scheduleIn.split(";")
        for day in days
          env.logger.info "Day: " + day
        if days?
          for day,i in days
            dayParameters = day.split(",")
            unless dayParameters.length is 4
              result.reason = "Schedule, invalid format of '#{dayParameters}'"
              return result
            dayOfWeek = dayParameters[0].trim()
            _day = @daysOfWeek[dayOfWeek]
            unless _day?
              result.reason = "Schedule, invalid day #{dayOfweek}"
              return result
            time = dayParameters[1].trim()
            _time = time.split(":")
            if _time?
              if Number _time[0] <0 or Number _time[0] > 23 or Number _time[1] < 0 or Number _time[1] > 59
                result.reason = "Schedule, invalid time format '#{time}' for '#{dayOfWeek}'"
                return result
            _duration = dayParameters[2].trim()
            if Number _duration < 0 or Number _duration > 1439
              result.reason = "Schedule, invalid duration value '#{dayParameters[2]}' for '#{dayOfWeek}'"
              return result
            _edgeCut = dayParameters[3].trim()
            if Number _edgeCut < 0 or Number _edgeCut > 1
              result.reason = "Schedule, invalid edgeCut value '#{dayParameters[3]}' for '#{dayOfWeek}'"
              return result
            result.schedule[_day] = [time, (Number _duration), (Number _edgeCut)]
          result.error = false
        return result
      catch err
        result.reason = "Error in checkAndComplete schedule " + err
        return result

    execute: (command, params) =>
      return new Promise((resolve, reject) =>
        env.logger.debug "Execute mower '#{@id}', command: " + command + ', params: ' + JSON.stringify(params,null,2)
        switch command
          when "start"
            om =
              cmd: 1
            outMsg = JSON.stringify(om)
            @plugin.landroidCloud.sendMessage(outMsg, @serial)
            resolve()
          when "pause"
            om =
              cmd: 2
            outMsg = JSON.stringify(om)
            @plugin.landroidCloud.sendMessage(outMsg, @serial)
            resolve()
          when "stop"
            om =
              cmd: 3
            outMsg = JSON.stringify(om)
            @plugin.landroidCloud.sendMessage(outMsg, @serial)
            resolve()
          when "schedule"
            if params.schedule?
              om =
                sc:
                  d: params.schedule
              outMsg = JSON.stringify(om)
              @plugin.landroidCloud.sendMessage(outMsg, @serial)
              @setSchedule(params.schedule)
              resolve()
            else
              reject()
          when "raindelay"
            if params.raindelay?
              om =
                rd: Number params.raindelay
              outMsg = JSON.stringify(om)
              @plugin.landroidCloud.sendMessage(outMsg, @serial)
              resolve()
            else
              reject()
          else
            reject()
      )

    setAttr: (attr, _status) =>
      #unless @attributeValues[attr] is _status
      @attributeValues[attr] = _status
      @emit attr, @attributeValues[attr]


    setSchedule: (schedule) =>
      #env.logger.info "Schedule: " + JSON.stringify(schedule,null,2)
      _nextMowe = "not scheduled"
      checkDate = Moment().day()
      for i in [0..7]
        if checkDate >6 then checkDate = 0
        if schedule[checkDate][1] > 0
          if i is 0 # is today
            time = (String schedule[checkDate][0]).split(":")
            if (Number time[0]) > Moment().hour() and (Number time[1]) > Moment().minute()
              _nextMowe = (Moment().add(i, 'days').format('dddd')).toLowerCase() + " " + schedule[checkDate][0]
              if Boolean schedule[checkDate][2]
                _nextMowe = _nextMowe + " " + "with edgeCut"
              @setAttr('nextMowe', _nextMowe)
              return
          else
            _nextMowe = (Moment().add(i, 'days').format('dddd')).toLowerCase() + " " + schedule[checkDate][0]
            if Boolean schedule[checkDate][2]
              _nextMowe = _nextMowe + " " + "with edgeCut"
            @setAttr('nextMowe', _nextMowe)
            return
        checkDate +=1
      @setAttr('nextMowe', _nextMowe)


    destroy: ->
      
      super()


  class LandroidActionProvider extends env.actions.ActionProvider

    constructor: (@framework) ->


    parseAction: (input, context) =>
      mowerDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class is "LandroidMower").value()
      @mowerDevice = null
      match = null
      @command = ""
      @params = {}

      setCommand = (command) =>
        @command = command

      setRainDelay = (m, delay) =>
        if delay < 0
          context?.addError("Minimum raindelay is 0")
          return
        if delay > 300
          context?.addError("Maximum raindelay is 300")
          return
        @params["raindelay"] = delay
        setCommand("raindelay")
        match = m.getFullMatch()
        return

      setScheduleVar = (m, tokens) =>
        @params["schedulevar"] = tokens
        env.logger.debug "ScheduleVars " + tokens #@params["schedulevar"]
        setCommand("schedule")
        match = m.getFullMatch()
        return

      setScheduleString = (m, tokens) =>
        @params["schedulestring"] = tokens
        setCommand("schedule")
        match = m.getFullMatch()
        _result = @mowerDevice.checkAndCompleteSchedule(tokens)
        if _result.error
          context?.addError(_result.reason)

      m = M(input, context)
        .match('mower ')
        .matchDevice(mowerDevices, (m, d) =>
          # Already had a match with another device?
          if mowerDevice? and mowerDevice.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          @mowerDevice = d
        )
        .or([
          ((m) =>
            return m.match(' start', (m) =>
              setCommand("start")
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' pause', (m) =>
              setCommand("pause")
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' stop', (m) =>
              setCommand("stop")
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' raindelay ')
              .matchNumber(setRainDelay)                
          ),
          ((m) =>
            return m.match(' schedule ')
              .or([
                ((m) =>
                  return m.matchVariable(setScheduleVar)
                ),
                ((m) =>
                  return m.matchString(setScheduleString)
                )
              ])         
          )
        ])

      if m.hadMatch()
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new LandroidActionHandler(@framework, @mowerDevice, @command, @params)
        }
      else
        return null


  class LandroidActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @mowerDevice, @command, @params) ->

    executeAction: (simulate) =>
      if simulate
        return __("would execute command \"%s\"", @command)
      else
        unless @mowerDevice.mowerOnline
          return __("Rule not executed, mower is offline")
        _params = @params
        if @command is "schedule"
          if _params.schedulevar?
            _var = (_params.schedulevar).slice(1) if (_params.schedulevar).indexOf('$') >= 0
            _scheduleString = @framework.variableManager.getVariableValue(_var)
          else if _params.schedulestring?
            _scheduleString = _params.schedulestring
          else
            return __("\"%s\" schedule string is missing") + err            
          if _scheduleString?
            schedule = @mowerDevice.checkAndCompleteSchedule(_scheduleString)
            if not schedule.error
              _params.schedule = schedule.schedule
              @mowerDevice.execute(@command, _params)
              .then(()=>
                return __("\"%s\" Executed mower command ", @command)
              ).catch((err)=>
                env.logger.debug "Error in mower execute " + err
                return __("\"%s\" Rule not executed mower offline") + err
              )
            else
              return __("\"%s\" Schedule is not valid ", _schedule.reason)
          else
            return __("\"%s\" Schedule variable does not excist ", _params.schedulevar)
        else
          @mowerDevice.execute(@command, _params)
          .then(()=>
            return __("\"%s\"Executed mower command ", @command)
          ).catch((err)=>
            env.logger.debug "Error in mower execute " + err
            return __("\"%s\" Rule not executed mower offline") + err
          )

  landroidPlugin = new LandroidPlugin
  return landroidPlugin
