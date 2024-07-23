#!/bin/bash -e

PATH=/usr/local/bin:$PATH

vers=12.26
url=https://exiftool.org/Image-ExifTool-$vers.tar.gz
tarfile="$(basename "$url")"
tardir="$(basename "$url" .tar.gz)"
bindir=/usr/local/bin
libdir=/usr/local/lib/perl5/site_perl
reinstall=false

while [ -n "$1" ]; do
    case "$1" in
        --reinstall) reinstall=true; shift ;;
        *) echo "Unrecognized argument: $1" 1>&2; exit 1 ;;
    esac
done

if ! $reinstall && [ "$(exiftool -ver || :)" = "$vers" ]; then
    exit 0
fi

cd /tmp
rm -rf "$tarfile" "$tardir"
wget -q "$url"
tar xf "$tarfile"
cd "$tardir"
(cd lib && tar -c * | tar -C "$libdir" -x)
cp exiftool "$bindir"
test "$(exiftool -ver)" = "$vers"
