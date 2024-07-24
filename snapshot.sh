#!/bin/bash -e

force=false
private=family-orchestration
public=${private}-public

while [ -n "$1" ]; do
    case "$1" in
        "--force") shift; force=true ;;
        *) echo "Unrecognized argument $1" 1>&2; exit 1 ;;
    esac
done

cd ~/src/$public
if ! $force && [ -n "$(git status --porcelain 2>&1)" ]; then
    echo "~/src/$public is not clean" 1>&2
    exit 1
fi
git checkout main
git pull || $force

cd ~/src/$private
if ! $force && [ -n "$(git status --porcelain 2>&1)" ]; then
    echo "~/src/$private is not clean" 1>&2
    exit 1
fi

exclude=$(git submodule | awk '{print "--exclude=/" $2}')
rsync -av --cvs-exclude --exclude /.ansible-facts/ $exclude ./ ~/src/$public/
