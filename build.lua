#!/usr/bin/env luajit

local log = require "lib.log"

local function command(program)
    local k = assert(io.popen("whereis " .. program))

    if #k:read() <= #program+1 then
        log.fatal("Program %s is not in $PATH or unsupported!", program)
        os.exit(255)
    end

    k:close()

    return function (...)
        local t = table.concat({ program, ... }, " ")
        print(">> " .. t)

        local k = assert(io.popen(t))
        local o = k:read()
        k:close()

        return o
    end
end

local zip   = command "zip"
local cd    = command "cd"
local mv    = command "mv"
local rm    = command "rm"
local mkdir = command "mkdir"
local echo = command "echo"

mkdir("-p .temp/")
mkdir("-p out/")

local love_generated = false

local function build_love()
    log.info("Generating Löve file...")

    if love_generated then
        return log.info("Löve file already generated.")
    end
    love_generated = true

    rm("-rf .temp/*")
    local rsync = command "rsync"

    rsync("-r --exclude-from=love_ignore * .temp")
    mv(".temp/assets/*.txt .temp")
    rm("-f out/above.love")
    zip("-r -9 out/above.love .temp/*")

    -- rsync -r --exclude-from=love_ignore * .temp
	-- mv .temp/assets/*.txt .temp
	-- echo HELLO I AM A NORMAL FILE > .temp/THIS_IS_A_RELEASE_BUILD
	-- rm out/above.love
	-- cd .temp/ && zip -r -9 ../out/above.love * 
	-- @echo -e ${GREEN}///// BUILT LÖVE${NC}
end

local lovelink = "https://github.com/love2d/love/releases/download/11.4/love-11.4-"
local function fetch_love2d(file, out)
    local wget = command "wget"

    mkdir("-p cache")

    wget("-nc", lovelink..file, "-O cache/love."..(out or file))
end

local function _windows(arch)
    log.info("Creating binary for %i bits Windows", arch)
    rm("-rf .temp/*")
    fetch_love2d("win"..arch..".zip")
    build_love()

    local cat = command "cat"
    local unzip = command "unzip"
    unzip("-j cache/love.win"..arch..".zip", "-d .temp/ -x *.ico *changes.txt *readme.txt *lovec.exe")
    cat(".temp/love.exe out/above.love > .temp/above.exe")
end

local function build_win32()
    _windows("32")
end

local function build_win64()
    _windows("64")
end

local function build_appimage()
    log.info("Creating AppImage.")

    rm("-rf .temp/*")
    fetch_love2d("x86_64.AppImage", "appimage")

    local appimagetool = command "appimagetool"
end

local function everything()
    build_love()
    build_win32()
    build_win64()
    build_appimage()
end

local function run()
    local love = command "love"

    love(".")
end

local function cleanup()
    rm("-rf cache/")
    rm("-rf out/")
end


local list
local function help()
    print("./build.lua [target1] [target2] [target3] ...\n")
    print("[Available targets]:")
    for name in pairs(list) do
        print("  > " .. name)
    end
end

list = {
    help     = help,
    cleanup  = cleanup,
    run      = run,
    love     = build_love,

    win32    = build_win32,
    win64    = build_win64,

    appimage = build_appimage,

    everything = everything
}

if #arg == 0 then
    return help()
end

local skipped = {}
for _, target in ipairs(arg) do
    local v = list[target]
    if v then
        v()
    else
        table.insert(skipped, target)
    end
end

if #skipped > 0 then
    local txt_skipped = table.concat(skipped, ", ")
    log.fatal("Targets [%s] were invalid.", txt_skipped)
end

if #skipped == #arg then
    help()
end
