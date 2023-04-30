$(shell mkdir -p out)
$(shell mkdir -p cache)
$(shell mkdir -p .temp)

GREEN='\033[0;32m'
NC='\033[0m'

love: # REQUIRES RSYNC
	rm -rf .temp/*
	rsync -r --exclude-from=love_ignore * .temp
	rm out/above.love
	cd .temp/ && zip -r -9 ../out/above.love * 
	@echo -e ${GREEN}///// BUILT LÖVE${NC}

win32: love # REQUIRES RSYNC, WGET, UNZIP
	rm -rf .temp/*
	wget -nc https://github.com/love2d/love/releases/download/11.4/love-11.4-win32.zip -O cache/love.win32.zip
	unzip -j cache/love.win32.zip -d .temp/ -x *.ico *changes.txt *readme.txt *lovec.exe
	cat .temp/love.exe out/above.love > .temp/above.exe
	rm .temp/love.exe
	cd .temp/ && zip -r -9 ../out/above.win32.zip *
	@echo -e ${GREEN}///// BUILT WIN32 ZIP${NC}

win64: love # REQUIRES RSYNC, WGET, UNZIP
	rm -rf .temp/*
	wget -nc https://github.com/love2d/love/releases/download/11.4/love-11.4-win64.zip -O cache/love.win64.zip
	unzip -j cache/love.win64.zip -d .temp/ -x *.ico *changes.txt *readme.txt *lovec.exe
	cat .temp/love.exe out/above.love > .temp/above.exe
	rm .temp/love.exe
	cd .temp/ && zip -r -9 ../out/above.win64.zip *
	@echo -e ${GREEN}///// BUILT WIN64 ZIP${NC}

appimage: love # REQUIRES RSYNC, WGET, GLIBC, APPIMAGETOOL
	rm -rf .temp/*
	wget -nc https://github.com/love2d/love/releases/download/11.4/love-11.4-x86_64.AppImage -O cache/love.appimage
	chmod +x cache/love.appimage
	cd .temp && ../cache/love.appimage --appimage-extract # i hate appimages.
	cd ..
	cat .temp/squashfs-root/bin/love out/above.love > .temp/squashfs-root/bin/above
	chmod +x .temp/squashfs-root/bin/above
	rm .temp/squashfs-root/bin/love .temp/squashfs-root/love.desktop
	cp assets/game.desktop .temp/squashfs-root/love.desktop
	appimagetool .temp/squashfs-root out/above.appimage
	@echo -e ${GREEN}///// BUILT 64 BIT APPIMAGE${NC}

everything: love win32 win64 appimage

run: # REQUIRES LÖVE AND LOVE :)
	love .

.ONESHELL: 