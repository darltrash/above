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



return fam