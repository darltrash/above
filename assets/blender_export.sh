#!/bin/bash

cd assets/

flatpak info org.blender.Blender 
if [ $? -eq 0 ]; then
    BLENDER="flatpak run org.blender.Blender"
else
    BLENDER="blender"
fi

shopt -s nullglob
for i in mod/*.blend; do
	$BLENDER $(realpath $i) --background --python $(realpath bpy_export.py) -- $(realpath ${i%.blend}.exm)
done
