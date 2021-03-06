# pimatic-landroid
Pimatic plugin for Worx Landroid mower

This plugin lets you control and get status info from a Landroid mower. Supported mowers are mowers that can be controlled via the Landroid app and are wifi connected to the Worx cloud.
This plugin is tested with a Landroid M500 and should work will all cloud connected Landroid mowers.

After downloading the Landoid app, you can register in the app with your email and password.
After registration you can add your mower in the app, configure the wifi and other settings.

When these steps are done you can configure the pimatic-landoid plugin.

## Config of the plugin
```
{
  email:    "The email address for your Landroid account"
  password: "The password of your Landroid account"
  debug:    "Debug mode. Writes debug messages to the Pimatic log, if set to true."
}
```

## Config of a LandroidMower device

Mowers are added via the discovery function. Per mower a LandroidMower is discovered unless the device is already in the config.
The automatic generated Id must not change. Its the unique reference to your mower. You can change the Pimatic device name after you have saved the device. This is the only device variable you may change!
The following data is automatically generated on device discovery and should not be changed!

```
{
  serial:       "Serialnumber of the mower"
  mac:          "Mac address of the mower"
  landroid_id:  "Landroid ID number of the mower"
  command_in:   "Mqtt command-in string"
  command_out:  "Mqtt command-out string"
}
```

The following variables (attributes) are available in the gui / pimatic.

```
cloud:              "If plugin is connected or disconnected to the Worx-landroid cloud"
status:             "Actual status of the mower (idle, mowing, etc)"
mower:              "Mower offline or online"
rainDelay:          "Delay after rain, before mowing (minutes)"
totalTime:          "TotalTime the mower has mowed (minutes)"
totalDistance:      "TotalDistance the mower has mowed (meters)"
totalBladeTime:     "TotalBladeTime the mower has mowed (minutes)"
battery:            "Battery level (0-100%)"
batteryCharging:    "If true battery is charging"
batteryTemperature: "Battery temperature of mower"
wifi:               "Wifi strenght at the mower (dBm)"
```
The mower can be controller and configured via rules.
The action syntax is:
```
mower <mower-id>
  [start|pause|stop]
  [raindelay] <raindelay-number>
  [schedule] $schedule-variable | "schedule string"
```

The schedule can be set for a week starting at sunday till saturday. This schedule is repeated every week.
The $schedule-variable contains a string with one or more days, separated by a semi-colon (;)
The format for one day is:

```
<day-of-week>, <time-string>, <duration>, <edgeCut>

valid values:
  <day-of-week>:  [sunday|monday|tuesday|wednesday|thursday|friday|saturday]
  <time-string>:  00:00 - 23:59
  <duration>:     0 - 1439 (minutes)
  <edgeCut>:      0 or 1
```
for example if you want to set the mower for tuesday and friday at 10:00 for 1 hour with edgeCutting,
the command is:
```
mower <mower-id> schedule $schedule-variable
$schedule-variable = tuesday, 10:00, 60, 1; friday, 10:00, 60, 1
```
or directly with a string in the action part of a rule

```
mower <mower-id> schedule "tuesday, 10:00, 60, 1; friday, 10:00, 60, 1"
```
---
The plugin is partly based on ioBroker.worx and homebridge-landroid

You could backup Pimatic before you are using this plugin!

__The minimum requirement for this plugin is node v8!__
