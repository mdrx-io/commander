#!/usr/bin/env bash

# Gets the absolute path of the script (not where it's called from)
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TOPDIR=$DIR/..

### start build ###
echo ""
echo "##### Building Commander... ######"

### check tools ###
echo -n "Checking system for dart-sdk...."
command -v pub >/dev/null 2>&1 || {
	echo "FAIL";
	echo "Please install dart-sdk, add bin to PATH, and restart this script. Aborting."
	exit 1;
}
echo "OK"
echo -n "Checking system for cleancss...."
command -v cleancss >/dev/null 2>&1 || {
	echo "FAIL";
	echo "Please install cleancss (npm -g install clean-css) and restart this script. Aborting."
	exit 1;
}
echo "OK"

### global ###
cd $TOPDIR

echo -n "Getting app dependencies........"
pub get > /dev/null
echo "OK"

### cmdr ###
cd $TOPDIR/bin

echo -n "Building (minifying) cmdr......."
dart2js --output-type=dart --categories=Server --minify -o cmdr cmdr.dart > /dev/null
rm cmdr.deps
sed -i '1i#!/usr/bin/env dart' cmdr
chmod +x cmdr
echo "OK"

### gui ###
cd $TOPDIR/web

echo -n "Getting more gui deps..........."
if [ ! -d "src-min-noconflict" ]; then
	git clone --quiet https://github.com/ajaxorg/ace-builds.git
	cd ace-builds
	# make sure we're using package 03.03.15
	git checkout --quiet beb9ff68e397b4dcaa1d40f79651a063fc917736
	mv src-min-noconflict ../src-min-noconflict
fi
cd $TOPDIR/web
rm -rf ace-builds
echo "OK"

cd $TOPDIR/

echo -n "Building (minifying) gui........"
WEB=$TOPDIR/web
cat $WEB/css/glyphicons.css $WEB/css/cosmos-bootstrap.min.css $WEB/css/main.css | cleancss -o $WEB/css/cmdr.css
pub build > /dev/null
echo "OK"

echo -n "Cleaning up gui................."
BUILD=$TOPDIR/build/web
mkdir -p $BUILD/fonts
cp $WEB/packages/bootjack/fonts/glyphicons-halflings-regular.* $BUILD/fonts/
rm $BUILD/css/cosmos-bootstrap.min.css $BUILD/css/main.css $BUILD/css/glyphicons.css
sed -i '/glyphicons.css/d' $BUILD/index.html
sed -i '/bootstrap.min.css/d' $BUILD/index.html
sed -i 's/main.css/cmdr.css/g' $BUILD/index.html
sed -i 's/main.dart/main.dart.js/g' $BUILD/index.html
echo "OK"

### done ###
cd $TOPDIR
echo ""
echo "##### Build complete. ############"
