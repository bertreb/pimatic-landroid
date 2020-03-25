# #pimatic-landroid configuration options
module.exports = {
  title: "pimatic-landroid configuration options"
  type: "object"
  properties:
  	email:
      description: "The Landroid cloud email"
      type: "string"
  	password:
      description: "The landroid cloud password"
      type: "string"
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false
}
