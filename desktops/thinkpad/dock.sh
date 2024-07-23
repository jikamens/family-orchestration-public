#!/bin/bash

# Sigh. This is hideously complicated because we get all sorts of
# duplicate udev events with weird timing whenever the laptop is
# docked or undocked, and because udev will wait on a udev script
# until it and all of the processes in its process group exit. So
# here's what we do:
#
# 1. When we are invoked with ACTION=add or ACTION=remove, then we
#    invoke ourselves with ACTION=monitor with `at now` and exit, to
#    escape into a different process group so udev won't wait on us.
#    Note: I tried using `setsid --fork` instead of `at now` and it
#    didn't work; apparently even a new subprocess in a new process
#    group isn't enough to get udev not to wait. Grr!
# 2. Try to acquire the lock. If it fails, then exit immediately.
#    Lockfiles older than 60 seconds are assumed to be stale and are
#    removed.
# 3. Ten seconds after acquiring the lock, check if lsusb agrees with
#    ACTION, i.e., if ACTION is `add`, then make sure the device is
#    present, and otherwise, make sure it's absent.
# 4. If lsusb and ACTION disagree, then flip the contents of ACTION,
#    wait five more seconds, and go to step 3.
# 5. Otherwise, suspend.

ff=/var/run/docked.lock
lf=/tmp/dock.log
device=17ef:3071
leave_on_file=/tmp/do-not-suspend

pid=$$

log() {
    echo $(date): $pid "$@" >>$lf
}

checkusb() {
    log checking if lsusb matches $ACTION
    if lsusb -d $device &>/dev/null; then
        if [ $ACTION = add ]; then
            log match: lsusb success, ACTION=$ACTION
            return 0
        fi
        log no match: lsusb success, ACTION=$ACTION, flipping ACTION
        ACTION=add
        return 1
    fi
    if [ $ACTION = remove ]; then
        log match: lsusb failure, ACTION=$ACTION
        return 0
    fi
    log no match: lsusb failure, ACTION=$ACTION, flipping ACTION
    ACTION=remove
    return 1
}

case $ACTION in
    add|remove)
        log invoked with ACTION=$ACTION, queuing monitor task and exiting
        echo REAL_ACTION=$ACTION ACTION=monitor $0 | at now
        exit
        ;;
    monitor)
        ACTION=$REAL_ACTION
        ;;
    *)
        log Unrecognized action $ACTION, exiting
        exit 1
        ;;
esac

log starting

if ! checkusb; then
    log initial state does not match ACTION, exiting
    exit 1
fi

if ! lockfile -r 0 -l 60 $ff &>/dev/null; then
    log locked, exiting
    exit 1
fi

log lock acquired
trap "log removing $ff; rm -f $ff" EXIT
log first sleep
sleep 10
while ! checkusb; do
    log no match sleep
    sleep 5
done
if [ $ACTION = remove ]; then
    if [ -f $leave_on_file ]; then
        log "not suspending because $leave_on_file exists; removing it"
        rm -f $leave_on_file
        exit
    fi
    log suspending
    systemctl suspend
    log woke from suspend, exiting
else
    log ACTION=$ACTION, exiting
fi
