-- such a cool fucking name isnt it

local bitser = require "lib.bitser"
local log = require "lib.log"

local permanence = {}
permanence.data = {
    [0] = "Hello! Careful with not breaking things!"
}

lf.setIdentity("meadows")

log.info("Savefiles at '%s'", lf.getAppdataDirectory())

permanence.save = function()
    local file = ".SAVE" .. permanence.slot
    lf.write(file, bitser.dumps(permanence.data))
    log.info("Saving '%s'", file)
end

permanence.load = function(slot)
    local file = ".SAVE" .. slot
    log.info("Loading save '%s'", file)

    local data, err = lf.read(file)
    if not data then return end

    permanence.data = assert(bitser.loads(data))
    permanence.slot = slot
    return true
end

return permanence
