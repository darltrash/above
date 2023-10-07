local dialog = require "dialog"
local log = require "lib.log"

local scripts = {}

scripts.spawn = function (fnc, after, ...)
    log.info("📜 Spawned routine \"%s\"", fnc)

    scripts.name = "<ANONYMOUS>"
    if type(fnc) == "string" then
        scripts.name = fnc
        fnc = require("scripts."..fnc)
    end

    scripts.coroutine = coroutine.create(setfenv(fnc, scripts.env))
    coroutine.resume(scripts.coroutine, ...)

    scripts.after = after
end

scripts.update = function ()
    if not scripts.coroutine then return end

    local ok = coroutine.resume(scripts.coroutine)
    if not ok then
        scripts.coroutine = nil
        scripts.name = nil
        if scripts.after then
            scripts.after()
            scripts.after = nil
        end
    end
end

scripts.env = {
    permanence = require "permanence",
    lang = require "language",

    math   = math,
    string = string,
    error  = error,
    assert = assert,
    log    = log,

    await = function (a) -- WAIT UNTIL CALLBACK RETURNS TRUE
        while not a() do
            coroutine.yield()
        end
    end,

    spawn = function (fnc, ...)
        local c = scripts.coroutine
        scripts.spawn(fnc, ...)
        while scripts.coroutine do
            coroutine.yield()
        end
        scripts.coroutine = c
    end,

    say = function (...)
        dialog:say(...)
    end,

    ask = function (...)
        return dialog:ask(...)
    end,

    display = function (...)
        dialog:display(...)
    end
}

return scripts