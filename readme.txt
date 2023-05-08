above.

How to build:
    - Windows (x86 and x86_64):
        Requirements: Some posix-esque interface, WGET, Make, zip, unzip, rsync, git

        Command:
            git clone --recurse-submodules https://github.com/darltrash/above
            make win32 # change to win64 if you want 64 bit binaries

    - Linux (Appimage, GLIBC 64 bits):
        Requirements: Linux/WSL (GLIBC), WGET, Make, Appimagetool, zip, rsync, git

        Command:
            git clone --recurse-submodules https://github.com/darltrash/above
            make appimage

    - Everything else:
        Requirements: Some posix-esque interface, Make, zip, rsync, git

        Command:
            git clone --recurse-submodules https://github.com/darltrash/above
            make love

How to run without building:
    - Fetch a binary from the itch.io page

    - Install Löve from love2d.org or a package manager, 
        Download this repo as a zip and rename it from .zip to .love,
        Execute the .love file with Löve

