# pimatic-landroid
Pimatic plugin for Worx Landroid mower

This plugin lets you control and get status info from a Landroid mower. Supported mowers are mowers that can be controlled via the Landroid app and are wifi connected to the Worx cloud.
This plugin is tested with a Landroid M500 and should work will all cloud connected Landroid mowers.

After downloading the Landoid app, you can registeren in the app with your email and password.
After registration you can add your mower in the app, configure the wifi and some settings.

When these steps are done you can config the pimatic-landoid plugin.

## Config of the plugin
```
{
  email:        "The email address for your Landroid account"
  password:     "The password of your Landroid account"
  debug:        "Debug mode. Writes debug messages to the Pimatic log, if set to true."
}
```

## Config of a LandroidMower device

Mowers are added via the discovery function. Per mower a LandroidMower is discovered unless the device is already in the config.
The automatic generated Id must not change. Its the unique reference to your mower. You can change the Pimatic device name after you have saved the device. This is the only device variable you may change!
The following dat is automatically generated on device discovery and should not be changed!

```
{
  serial: "The serialnumber of the mower"
  mac: "The mac address of the mower"
  landroid_id: "The Landroid ID number of the mower"
  command_in: "The mqtt command-in string"
  command_out: "The mqtt command-out string"
}
```

The following variables (attributes) are available in the gui / pimatic.

```
cloud: "If plugin is connected or disconnected to the Worx-landroid cloud"
status: "Actual status of the mower"
mower: "If mower is offline or online"
language: "The used/configured language"
rainDelay: "The delay after rain, before mowing (minutes)"
batteryCharging: "If true battery is charging"
totalTime: "The totalTime the mower has mowed (minutes)"
totalDistance: "The totalDistance the mower has mowed (meters)"
totalBladeTime: "The totalBladeTime the mower has mowed (minutes)"
battery: "Battery level (0-100%)"
batteryTemperature: "Battery temperature of mower"
wifi: "Wifi strenght at the mower (dBm)"
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
In the $schedule-variable contains a string with one or more days, separated by a semi-colon (;)
The format for a day is

```
<day-of-week>, <time-string>, <duration>, <edgeCut>; .....
```
Valid values:
\<day-of-week> are [sunday|monday|tuesday|wednesday|thursday|friday|saturday].
\<duration>: 0 - 1439 (minutes)
\<edgeCut>: 0 or 1
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
