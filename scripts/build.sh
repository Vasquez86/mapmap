#!/bin/bash
# Install qt4-default qt4-qmake
# On Mac, install it from http://qt-project.org/downloads
# set -o verbose

set -euo pipefail

cd $(dirname $0)
cd ..

#Verify this version matches folder name.
qtversion=5.10.1

find_qmake() {
    # Prefer an explicitly provided QMAKE binary, then common Qt5 names.
    for candidate in "${QMAKE:-}" qmake-qt5 qmake; do
        if [ -n "$candidate" ] && command -v "$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done

    cat <<'EOF' >&2
qmake (Qt5) was not found.
On Ubuntu, install the Qt and GStreamer development packages, e.g.:
  sudo apt-get install -y \\
      qtbase5-dev qttools5-dev-tools qtmultimedia5-dev \\
      libqt5opengl5-dev qtwebengine5-dev libqt5multimedia5-plugins \\
      libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \\
      gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-plugins-good

Then re-run this script.
EOF
    return 1
}

ensure_gstreamer() {
    if pkg-config --exists gstreamer-1.0 gstreamer-base-1.0 gstreamer-app-1.0 gstreamer-pbutils-1.0; then
        return 0
    fi

    cat <<'EOF' >&2
GStreamer development files were not detected by pkg-config.
On Ubuntu, install them with:
  sudo apt-get install -y libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \\
      gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-plugins-good

Then re-run this script.
EOF
    return 1
}

do_create_dmg() {
    if [ -f DMGVERSION.txt ]
    then
        echo "Using DMGVERSION.txt"
        cat DMGVERSION.txt
    else
        echo 1 > DMGVERSION.txt
    fi
    VERSION=$(cat VERSION.txt)
    DMGVERSION=$(cat DMGVERSION.txt)
    DMGDIR=MapMap-${VERSION}-${DMGVERSION}
    echo "Creating directory ${DMGDIR}"
    rm -rf $DMGDIR
    mkdir -p $DMGDIR
    cp -R MapMap.app ${DMGDIR}
    cp README.md ${DMGDIR}/README.txt
    cp NEWS ${DMGDIR}/NEWS.txt
    cp resources/macOS/Get\ GStreamer\ macOS.url ${DMGDIR}/
    hdiutil create \
        -volname ${DMGDIR} \
        -srcfolder ${DMGDIR} \
        -ov -format UDZO \
        ${DMGDIR}.dmg
    # Let's also create a zip archive:
    zip -r ${DMGDIR}_macOS.zip ${DMGDIR}
}

do_fix_qt_plugins_in_app() {
    appdir=./MapMap.app
    qtdir=~/Qt/${qtversion}/clang_64
    # install libqcocoa library
    mkdir -p $appdir/Contents/PlugIns/platforms
    cp $qtdir/plugins/platforms/libqcocoa.dylib $appdir/Contents/PlugIns/platforms
    # fix its identity and references to others
    install_name_tool -id @executable_path/../PlugIns/platforms/libqcocoa.dylib $appdir/Contents/PlugIns/platforms/libqcocoa.dylib
    for qtframework in QtWidgets, QtGui, QtCore, QtXml, QtOpenGL; do
      framework = "$qtframework.framework/Versions/5/$qtframework"
      echo "Processing $framework"
      install_name_tool -change $qtdir/lib/$framework @executable_path/../Frameworks/$framework
    done
}

unamestr=$(uname)

if [[ $unamestr == "Darwin" ]]; then

    echo "Please enter password to restart Finder. This will set the application icon later ..."

    #prompt for sudo password before longer operations
    sudo echo

    #MAKE_CFLAGS_X86_64+="-Xarch_x86_64 -mmacosx-version-min=10.7"
    #QMAKE_CFLAGS_PPC_64+="-Xarch_ppc64 -mmacosx-version-min=10.7"
    #export MAKE_CFLAGS_X86_64
    #export QMAKE_CFLAGS_PPC_64
    #export QMAKESPEC=macx-g++
    #export QMAKESPEC=macx-xcode
    qtbindir=~/Qt/${qtversion}/clang_64/bin/
    PATH=$PATH:${qtbindir}
    gstreamer="GStreamer.framework/Versions/1.0/lib/GStreamer"
    app="MapMap.app"

    # XXX
    #$qmake5 -config release -spec macx-llvm
    #$qmake5 -config debug -spec macx-llvm
    #$qmake5 -config release -spec macx-llvm
    #$qmake5 -config debug -spec macx-g++
    #qmake -config release -spec macx-g++

    # build program
    echo "Building program ..."
    echo "FIXME: you might need to run qmake in Qt Creator on macOS, and then run this script again"
    qmake -config release
    make -j4

    # Bundle Qt frameworks in app using macdeployqt
    echo "Bundling Qt ..."
    macdeployqt $app

    # Set application icon macOS
    echo "Applying Application Icon, restarting Finder ..."
    cp -f resources/macOS/info.plist ${app}/Contents/
    cp -f resources/macOS/mapmap.icns ${app}/Contents/Resources

    touch MapMap.app/

    #echo "Password Required to Restart Finder - this will set the applicaiton image ..."

    sudo killall Finder
    sudo killall Dock

    # Bundle GStreamer framework in app
    #echo "Bundling GStreamer ..."
    #cp -R /Library/Frameworks/GStreamer.framework ${app}/Contents/Frameworks/
    #install_name_tool -id @executable_path/../Frameworks/${gstreamer} ${app}/Contents/Frameworks/${gstreamer}
    #install_name_tool -change /Library/Frameworks/${gstreamer} @executable_path/../Frameworks/${gstreamer} ${app}/Contents/MacOs/MapMap

    # do_fix_qt_plugins_in_app
    echo "Creating DMG ..."
    do_create_dmg
elif [[ $unamestr == "Linux" ]]; then
    QMAKE_BIN=$(find_qmake)
    ensure_gstreamer
    "$QMAKE_BIN"
    make -j"$(nproc)"
fi
