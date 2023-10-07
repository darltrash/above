local anim = {
  "front1",
  "hmm",
  "front2",
  "itsme"
}
local a = 2
return function(self)
  display("Watch me CHANGE!")
  self.mesh_index = anim[a]
  a = a + 1
  if (a > #anim) then
    a = 1
  end
end
