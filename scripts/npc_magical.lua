local anim = {
  "front1",
  "hmm",
  "front2",
  "itsme"
}
local a = 2
return function(self)
  say("hello world!")
  a = ask("do you like penis", {
    "yes",
    "no"
  })
  if a == 1 then
    return say("ohmaga")
  else
    return say("ok, dumbass")
  end
end
