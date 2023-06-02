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

fam.hex = function (hex, alpha)
    local h = hex:gsub("#", "")
    return {
        (tonumber("0x"..h:sub(1,2))/255),
        (tonumber("0x"..h:sub(3,4))/255),
        (tonumber("0x"..h:sub(5,6))/255),
        alpha or 1
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

fam.animate = function (ticks, callback) -- fn(t)
    local start = lt.getTime()

    local i = 0
    repeat
        i = (lt.getTime() - start) / ticks
        callback(i)
        coroutine.yield()
    until i >= 1
end

fam.clamp = function (a, min, max)
    return math.max(min, math.min(max, a))
end

fam.aabb = function (x1,y1,w1,h1, x2,y2,w2,h2)
    return x1 < x2+w2 and
           x2 < x1+w1 and
           y1 < y2+h2 and
           y2 < y1+h1
end
  
fam.copy_into = function (from, into)
    for k, v in pairs(from) do
        into[k] = v
    end
end

return fam