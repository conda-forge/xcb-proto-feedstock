#! /bin/bash

set -e
set -x
IFS=$' \t\n' # workaround for conda 4.2.13+toolchain bug

# Adopt a Unix-friendly path if we're on Windows (see bld.bat).
[ -n "$PATH_OVERRIDE" ] && export PATH="$PATH_OVERRIDE"

# On Windows we want $LIBRARY_PREFIX in both "mixed" (C:/Conda/...) and Unix
# (/c/Conda) forms, but Unix form is often "/" which can cause problems.
if [ -n "$LIBRARY_PREFIX_M" ] ; then
    mprefix="$LIBRARY_PREFIX_M"
    if [ "$LIBRARY_PREFIX_U" = / ] ; then
        uprefix=""
    else
        uprefix="$LIBRARY_PREFIX_U"
    fi
else
    mprefix="$PREFIX"
    uprefix="$PREFIX"
fi

# On Windows we need to regenerate the configure scripts.
if [ -n "$CYGWIN_PREFIX" ] ; then
    am_version=1.15 # keep sync'ed with meta.yaml
    export ACLOCAL=aclocal-$am_version
    export AUTOMAKE=automake-$am_version
    autoreconf_args=(
        --force
        --install
        -I "$mprefix/share/aclocal"
        -I "$BUILD_PREFIX_M/Library/usr/share/aclocal"
    )
    # 2023/09: our automake-1.15 package provides a version of the py-compile
    # script that is so old that it's missing a modification that is required to
    # build on Python 3.12. But the source package's file does have it, so we
    # can avoid the issue by backing up that file and restoring it. The
    # intention is that the MSYS2 packages will be updated pretty soon
    # (~months), at which point it should be possible to remove this workaround.
    mv py-compile py-compile.bak
    autoreconf "${autoreconf_args[@]}"
    mv -f py-compile.bak py-compile
else
    # for other platforms we just need to reconf to get the correct achitecture
    echo libtoolize
    libtoolize
    echo aclocal -I $PREFIX/share/aclocal -I $BUILD_PREFIX/share/aclocal
    aclocal -I $PREFIX/share/aclocal -I $BUILD_PREFIX/share/aclocal
    echo autoconf
    autoconf
    echo automake --force-missing --add-missing --include-deps
    automake --force-missing --add-missing --include-deps

    export CONFIG_FLAGS="--build=${BUILD}"
fi

# The $pythondir variable is inserted into xcb-proto.pc. In newer automakes the
# default version of this variable references $PYTHON_PREFIX, which causes
# pkg-config to error out. Work around by setting it ourselves.
export am_cv_python_pythondir="$(python -c "import sysconfig; print(sysconfig.get_path('purelib'))")"

export PKG_CONFIG_LIBDIR=$uprefix/lib/pkgconfig:$uprefix/share/pkgconfig
configure_args=(
    $CONFIG_FLAGS
    --prefix=$mprefix
    --disable-dependency-tracking
    --disable-selective-werror
    --disable-silent-rules
)
./configure "${configure_args[@]}"
make -j$CPU_COUNT
make install
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
make check
fi

rm -rf $uprefix/share/doc/xcb-proto
