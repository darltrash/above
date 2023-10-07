local log = require "lib.log"
local toml = require "lib.toml"

local data = love.filesystem.read("language/en.toml")
local backup = toml.parse(data)
local strings = {}

local lang = {}

-- TODO: Clean this cursed code up.
lang.load = function (name)
    local k = function ()
        -- Tries to load file at save folder FIRST
        -- so unofficial translations can exist without
        -- having to modify the actual game

        local read = love.filesystem.read
        local f = read("language_"..name..".lua")
               or read("language/"..name..".lua")

        if not f then
            return false
        end

        local ok, l = pcall(toml.parse, f)
        if not ok then
            log.info("Could not read language file %s, error:\n\t%s", name, l)
            return false
        end

        return l
    end

    local l = k()
    local okay = l
    l = l or backup

    -- Default to backup (english)
    -- THIS ALSO MEANS that there can't be ANY 
    -- missing string in backup, NONE.
    for name, value in pairs(backup) do
        strings[name] = l[name] or value
    end

    return okay
end

lang.by_locale = function ()
    -- Default to english:

    local lang_str
    if love.system.getOS() == "Windows" then
        -- I'm not even going to bother with this shit, genuinely
        -- If someone wants to contribute with a solution, i'm open for it
        lang_str = "en"
    else
        lang_str = os.getenv("LANG") or "en"
        lang_str = lang_str:sub(1, 2):lower()
    end

    if not lang.load(lang_str) then
        log.info("Could not load '%s', defaulting to english.", lang_str)
    end
end

return setmetatable(lang, { __index = strings })