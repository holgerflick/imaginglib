#!/bin/bash

echo "Building Extension Demos using Free Pascal"

# Important! Set this dirs on your system 
SDLDIR=""
OPENGLDIR=""

ROOTDIR=".."
DEMOPATH="$ROOTDIR/Demos/ObjectPascal" 
UNITS="-Fu$ROOTDIR/Source -Fu$ROOTDIR/Source/JpegLib -Fu$ROOTDIR/Source/ZLib -Fu$DEMOPATH/Common -Fu$ROOTDIR/Source/Extensions -Fu$SDLDIR -Fu$OPENGLDIR"  
INCLUDE="-Fi$ROOTDIR/Source -Fi$SDLDir -Fi$OPENGLDIR" 
OUTPUT="-FE$ROOTDIR/Demos/Bin"
OPTIONS="-Sgi2dh -OG2 -Xs"

fpc $OPTIONS $OUTPUT "$DEMOPATH/SDLDemo/SDLDemo.dpr" $UNITS $INCLUDE -oSDLDemo
if test $? = 0; then
fpc $OPTIONS $OUTPUT "$DEMOPATH/OpenGLDemo/OpenGLDemo.dpr" $UNITS $INCLUDE -oOpenGLDemo
fi

if test $? = 0; then 
  echo "Extension demos successfuly build in Demos/Bin directory"
else
  echo "Error when building demos!"
fi

sh Clean.sh
