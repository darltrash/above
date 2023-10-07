->
    state.daytime = 0.6
    say "\nHELLO WORLD!\n\n~Welcome to the debug mode!"
    say "If you feel lost, disoriented or\nextremely powerful,\n\n*Do not call the police."
    display "this is a warning."

    assets.mus_guarded_place\setVolume 0.1
    assets.mus_guarded_place\play!

    entities["npc/freckles_test"].delete = true