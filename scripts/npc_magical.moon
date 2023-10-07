anim = {"front1", "hmm", "front2", "itsme"}
a = 2

=>
    display "Watch me CHANGE!"
    
    @mesh_index = anim[a]
    a += 1
    if (a > #anim)
        a = 1