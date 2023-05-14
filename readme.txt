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

    It is recommended to build or use a pre-built binary instead of
    running this project as-is, because it contains tons of "bloaty"
    things that only serve a purpose for development; such things
    being deleted in the built versions of this game.

Useful environment variables:
    To control above's engine directly you can use a set of specific
    environment variables, such as:

	ABOVE_LOW_END: Boolean, Disables post-processing if not null.
	ABOVE_DEBUG: Boolean, Enables debug mode if not null (does not work in prebuilt binaries).
	ABOVE_FPS: Boolean, Shows FPS if not null.
	ABOVE_LINEAR: Boolean, Makes everything look awful for no reason if not null.
	ABOVE_NO_POST: Boolean, Disables post-processing if not null.
	ABOVE_VOLUME: Number, Sets the audio volume globally (0 is mute, 1 is normal)
	ABOVE_FULLSCREEN: Boolean, Sets the fullscreen mode to on if not null
	ABOVE_SCALE: Number: Sets the downscaling amount, 1 is no downscaling.
	ABOVE_VSYNC: Number: Sets VSYNC, (0: No VSYNC, 1: Normal, 2: Half, etc)