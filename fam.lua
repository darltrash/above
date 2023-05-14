local fam = {}

fam.lerp = function (a, b, t)
    return a * (1-t) + b * t
end

fam.decay = function (value, target, rate, delta)
    return fam.lerp(target, value, math.exp(-math.exp(rate)*delta))
end

fam.sign = function (a)
    return (a > 0) and 1 or -1
end

fam.signz = function (a)
    return (a > 0) and 1 or (a < 0) and -1 or 0
end

fam.hex = function (hex, mul)
    local h = hex:gsub("#", "")
    mul = mul or 1
    return {
        (tonumber("0x"..h:sub(1,2))/255)*mul,
        (tonumber("0x"..h:sub(3,4))/255)*mul,
        (tonumber("0x"..h:sub(5,6))/255)*mul,
        1
    }
end

fam.split = function(str, sep)
    local t = { }

    for s in str:gmatch("([^"..(sep or "%s").."]+)") do
        table.insert(t, s)
    end

    return t
end

fam.wait = function (ticks)
    local start = lt.getTime()
	while (lt.getTime() - start) < ticks do
		coroutine.yield()
    end
end

return fam