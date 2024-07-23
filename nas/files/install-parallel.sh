#!/bin/bash -e

PATH=/usr/local/bin:$PATH

vers=20210522
url=https://gnu.mirror.constant.com/parallel/parallel-$vers.tar.bz2
tarfile="$(basename "$url")"
tardir="$(basename "$url" .tar.bz2)"
bindir=/usr/local/bin
libdir=/usr/local/lib/perl5/site_perl
reinstall=false

while [ -n "$1" ]; do
    case "$1" in
        --reinstall) reinstall=true; shift ;;
        *) echo "Unrecognized argument: $1" 1>&2; exit 1 ;;
    esac
done

if ! $reinstall && (parallel -V | grep -q -s "$vers"); then
    exit 0
fi

cd /tmp
rm -rf "$tarfile" "$tardir"
wget -q "$url"
tar xf "$tarfile"
cd "$tardir"
cp src/parallel "$bindir"
if ! (parallel -V | grep -q -s "$vers"); then
    echo "Install appears to have failed:" 1>&2
    parallel -V 1>&2
fi
