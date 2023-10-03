.DEFAULT_GOAL := run

$(shell mkdir -p out)
$(shell mkdir -p cache)
$(shell mkdir -p .temp)

GREEN='\033[0;32m'
NC='\033[0m'

generate-icons:
	rm -rf assets/img/icons/*
	flatpak run org.inkscape.Inkscape -w 512  -h 512  assets/img/icon.svg -o assets/img/icons/icon512.png
	flatpak run org.inkscape.Inkscape -w 256  -h 256  assets/img/icon.svg -o assets/img/icons/icon256.png
	flatpak run org.inkscape.Inkscape -w 128  -h 128  assets/img/icon.svg -o assets/img/icons/icon128.png
	flatpak run org.inkscape.Inkscape -w 32   -h 32   assets/img/icon.svg -o assets/img/icons/icon32.png
	flatpak run org.inkscape.Inkscape -w 16   -h 16   assets/img/icon.svg -o assets/img/icons/icon16.png
	optipng assets/img/icons/*
	png2icns assets/img/icons/icon.icns assets/img/icons/*

	convert assets/img/icons/icon128.png -bordercolor white -border 0 \
      \( -clone 0 -resize 16x16 \) \
      \( -clone 0 -resize 32x32 \) \
      \( -clone 0 -resize 48x48 \) \
      \( -clone 0 -resize 64x64 \) \
      -delete 0 -alpha off -colors 256 assets/img/icons/icon.ico

scripting:
	moonc scripts/*.moon

# TODO: Make this target produce only run ONCE per makefile execution!
love: # REQUIRES RSYNC, ZIP
	rm -rf .temp/*
	rsync -r --exclude-from=love_ignore * .temp
	mv .temp/assets/*.txt .temp
	echo HELLO I AM A NORMAL FILE > .temp/THIS_IS_A_RELEASE_BUILD
	rm out/above.love
	cd .temp/ && zip -r -9 ../out/above.love * 
	@echo -e ${GREEN}///// BUILT LÖVE${NC}

win32: love # REQUIRES RSYNC, WGET, ZIP, UNZIP
	rm -rf .temp/*
	wget -nc https://github.com/love2d/love/releases/download/11.4/love-11.4-win32.zip -O cache/love.win32.zip
	unzip -j cache/love.win32.zip -d .temp/ -x *.ico *changes.txt *readme.txt *lovec.exe
	cat .temp/love.exe out/above.love > .temp/above.exe
	rm .temp/love.exe
	cd .temp/ && zip -r -9 ../out/above.win32.zip *
	@echo -e ${GREEN}///// BUILT WIN32 ZIP${NC}

win64: love # REQUIRES RSYNC, WGET, ZIP, UNZIP
	rm -rf .temp/*
	wget -nc https://github.com/love2d/love/releases/download/11.4/love-11.4-win64.zip -O cache/love.win64.zip
	unzip -j cache/love.win64.zip -d .temp/ -x *.ico *changes.txt *readme.txt *lovec.exe
	cat .temp/love.exe out/above.love > .temp/above.exe
	rm .temp/love.exe
	cd .temp/ && zip -r -9 ../out/above.win64.zip *
	@echo -e ${GREEN}///// BUILT WIN64 ZIP${NC}

appimage: love # REQUIRES RSYNC, WGET, GLIBC, ZIP, APPIMAGETOOL
	rm -rf .temp/*
	wget -nc https://github.com/love2d/love/releases/download/11.4/love-11.4-x86_64.AppImage -O cache/love.appimage
	chmod +x cache/love.appimage
	cd .temp && ../cache/love.appimage --appimage-extract # i hate appimages.
	cd ..
	cat .temp/squashfs-root/bin/love out/above.love > .temp/squashfs-root/bin/above
	chmod +x .temp/squashfs-root/bin/above
	rm .temp/squashfs-root/bin/love .temp/squashfs-root/love.desktop .temp/squashfs-root/love.svg
	cp assets/game.desktop .temp/squashfs-root/love.desktop
	cp assets/img/icon.svg .temp/squashfs-root/meadows.svg
	appimagetool .temp/squashfs-root out/above.appimage
	@echo -e ${GREEN}///// BUILT 64 BIT APPIMAGE${NC}

# TODO: Fix this?
flatpak: love
	$(error NOT READY) # FOR NOW
	rm -rf .temp/*
	cp assets/flatpak.json .temp
	cp assets/game.desktop .temp
	cp out/above.love .temp

	flatpak-builder --user --install .temp/build-dir .temp/flatpak.json --ccache --force-clean

mac: love
	rm -rf .temp/*
	wget -nc https://github.com/love2d/love/releases/download/11.4/love-11.4-macos.zip -O cache/love.app.zip
	cd .temp/ && unzip ../cache/love.app.zip -x *.h *.hpp -d . && cd ..
	/bin/cp -rf assets/Info.plist .temp/love.app/Contents/
	cp out/above.love .temp/love.app/Contents/Resources
	rm -rf out/above.macos.zip
	cd .temp/ && zip -y -r -9 ../out/above.macos.zip love.app 

everything: love win32 win64 appimage mac

itch: everything
	rm -rf .temp/*
	mkdir .temp/win32
	unzip out/above.win32.zip -d .temp/win32
	butler push .temp/win32 darltrash/meadows:win32

	mkdir .temp/win64
	unzip out/above.win64.zip -d .temp/win64
	butler push .temp/win64 darltrash/meadows:win64

	butler push out/above.appimage darltrash/meadows:linux64
	butler push out/above.love darltrash/meadows:universal

clear:
	rm -rf out/
	rm -rf .temp

LOVE ?= love

maps: # REQUIRES BLENDER 2.90+
	chmod +x assets/blender_export.sh
	./assets/blender_export.sh

run: # REQUIRES LÖVE AND LOVE :)
	$(LOVE) .

.ONESHELL: 
