module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  http = require('http')
  fs = require('fs')
  path = require('path')
  _ = require('lodash')
  M = env.matcher
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

      for i in [1..7]
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
      @attributes =
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
        language:
          description: "The used language"
          type: "string"
          acronym: "language"
        rainDelay:
          description: "The delay after rain, before mowing"
          type: "number"
          acronym: "rainDelay"
          unit: "min"
        batteryCharging:
          description: "If true battery is charging"
          type: "boolean"
          acronym: "batteryCharging"
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

      @attributeValues = {}
      for i, _attr of @attributes
        #env.logger.info "i " + i + ", type: " + _attr.type
        do(_attr)=>
          switch _attr.type
            when "string"
              @attributeValues[i] = ""
            when "number"
              @attributeValues[i] = 0
            when "boolean"
              @attributeValues[i] = false
            else
              @attributeValues[i] = ""
          @_createGetter(i, =>
            return Promise.resolve @attributeValues[i]
          )
          @setAttr i, @attributeValues[i]

      @framework.on "after init", =>
        @setAttr("cloud","disconnected")
        @setAttr("mower","offline")

      @plugin.landroidCloud.on "mqtt", (mower, data)=>
        @processMowerMessage(mower, data)

      @plugin.landroidCloud.on "online",  (msg)=>
        env.logger.debug "online message received processing"
        @processMowerMessage(null,msg)
      @plugin.landroidCloud.on "offline",  (msg)=>
        env.logger.debug "offline message received processing"
        @processMowerMessage(null,msg)

      @plugin.landroidCloud.on "connect",  (data)=>
        @setAttr("cloud","connected")

      super()

    processMowerMessage: (mower, data) =>
      #env.logger.debug "processMowerMessage, mower: " + JSON.stringify(mower,null,2) + ", data: " + JSON.stringify(data,null,2)
      if mower?
        if mower.online?
          if mower.online 
            @setAttr("mower", "online")
            @mowerOnline = true
          else
            @setAttr("mower","offline")
            @mowerOnline = false
      if data?
        landroidDataset = new LandroidDataset(data)
        if landroidDataset.statusDescription?
          @setAttr("status",landroidDataset.statusDescription)
        if landroidDataset.rainDelay?
          @setAttr("rainDelay",Number landroidDataset.rainDelay)
        if landroidDataset.language?
          @setAttr("language",landroidDataset.language)
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
          env.logger.debug "mqtt schedule received"


    checkAndCompleteSchedule: (scheduleIn) =>
      return new Promise((resolve, reject) =>
        try
          tempSchedule = @emptySchedule
          days = scheduleIn.split(";")
          if days?
            for day,i in days
              dayParameters = day.split(",")
              dayOfWeek = (dayParameters[0].trimLeft()).trimEnd()
              _day = @daysOfWeek[dayOfWeek]
              unless _day?
                env.logger.debug "Schedule, unknown day '#{dayOfweek}'"
                reject()
              _time = dayParameters[1]
              _time = (_time.trimLeft()).trimEnd()
              _time2 = _time.split(":")
              if _time2?
                if Number _time2[0] <0 or Number _time2[0] > 23 or Number _time2[1] < 0 or Number _time2[1] > 59
                  env.logger.debug "Schedule, invalid time format '#{dayParameters[1]}' for day #{i}"
                  reject()
              _duration = dayParameters[2]
              _duration = (_duration.trimLeft()).trimEnd()
              if Number _duration < 0 or Number _duration > 1439
                env.logger.debug "Schedule, invalid duration value '#{dayParameters[2]}' for day #{i}"
                reject()
              _edgeCut = dayParameters[3]
              _edgeCut = (_edgeCut.trimLeft()).trimEnd()
              if Number _edgeCut < 0 or Number _edgeCut > 1
                env.logger.debug "Schedule, invalid edgeCut value '#{dayParameters[3]}' for day #{i}"
                reject()
              tempSchedule[_day] = [_time, (Number _duration), (Number _edgeCut)]
            resolve(tempSchedule)
        catch err
          env.logger.debug "Error in checkAndComplete schedule " + err
          reject()
      )

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
      env.logger.debug "Set attribute '#{attr}' to '#{_status}'"


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
        return

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
            _schedule = @framework.variableManager.getVariableValue(_var)
          else if _params.schedulestring?
            _schedule = _params.schedulestring
          else
            return __("\"%s\" schedule string is missing") + err            
          if _schedule?
            @mowerDevice.checkAndCompleteSchedule(_schedule)
            .then((schedule) =>
              _params.schedule = schedule
              @mowerDevice.execute(@command, _params)
              .then(()=>
                return __("\"%s\" Executed mower command ", @command)
              ).catch((err)=>
                env.logger.debug "Error in mower execute " + err
                return __("\"%s\" Rule not executed mower offline") + err
              )
            ).catch((err)=>
              return __("\"%s\" Schedule is not valid ", _schedule)
            )
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