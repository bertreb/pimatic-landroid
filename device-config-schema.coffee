module.exports = {
  title: "pimatic-sounds device config schemas"
  LandroidMower: {
    title: "LandroidMower config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties: {
      serial:
        description: "The serial number of the mower"
        type: "string"
      mac:
        description: "The mac address of the mower"
        type: "string"
      landroid_id:
        description: "The landroid id number of the mower"
        type: "number"
      product_id:
        description: "The product id of the mower"
        type: "number"
      command_in:
        description: "The mqtt comand_in topic"
        type: "string"
      command_out:
        description: "The mqtt comand_out topic"
        type: "string"
    }
  }
}
