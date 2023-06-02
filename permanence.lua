-- such a cool fucking name isnt it

local cbor = require "lib.cbor"
local log = require "lib.log"

local permanence = {}
permanence.data = {
    [0] = "Hello! Careful with not breaking things!"
}

lf.setIdentity("above")

log.info("Savefiles at '%s'", lf.getAppdataDirectory())

permanence.save = function ()
    local file = ".SAVE"..permanence.slot
    lf.write(file, cbor.encode(permanence.data))
    log.info("Saving '%s'", file)
end

permanence.load = function (slot)
    local file = ".SAVE"..slot
    log.info("Loading save '%s'", file)

    local data, err = lf.read(file)
    if not data then return end

    permanence.data = cbor.decode(data)
    permanence.slot = slot
    return true
end
 
return permanence