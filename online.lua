-- STATE OF THE MIND!!!

local sock = require "lib.sock"

local online = {}

local server, client
online.server = function (port, state)
    server = sock.newServer("*", port or 1337)

    server:on("connect", {
        level = state.map_name
    })
end

online.update = function ()
    local what = server or client
    if what then
        what:update()
    end
end

return online