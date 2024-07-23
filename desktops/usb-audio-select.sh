#!/bin/bash

# egrep expressions
SOURCE_EXCLUDE='ThinkPad_Dock_USB|UD-3900|LAPDOCK'
SINK_EXCLUDE='ThinkPad_Dock_USB|UD-3900|LAPDOCK'
PREFERRED_SOURCES=('Jabra_Link')
PREFERRED_SINKS=()

# http://blog.ostermiller.org/ubuntu-usb-audio/

# Automatically select USB sound devices 
# Copyright (C) 2013 Stephen Ostermiller
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, 
# Boston, MA  02110-1301, USA.

install() {
    if [ $EUID -ne 0 ]
    then
        echo "Error you are not the root user."
        echo "Run this install as root (or use sudo)"
        exit 1
    fi
    if [ ! `which play` ]
    then
         apt-get -y install sox
    fi
    script=`readlink -f $0`
    rulefile=/lib/udev/rules.d/99-usb-audio-auto-select.rules
    if [ -e $rulefile ]
    then
        echo "udev rule already exists: $rulefile"
    else
        echo "Creating udev rule: $rulefile"
        echo "ACTION==\"add\", SUBSYSTEM==\"usb\", DRIVERS==\"snd-usb-audio\", RUN+=\"$script\"" > $rulefile
        service udev restart
    fi
    rulefile=/usr/lib/pm-utils/sleep.d/99usbaudio    
    if [ -e $rulefile ]
    then
        echo "pm-utils sleep/wake rule already exists: $rulefile"
    else
        echo "Creating pm-utils sleep/wake rule: $rulefile"
        echo -e "#!/bin/sh \n case \"\$1\" in \n 'resume' | 'thaw') \n $script \n ;; \n esac" > $rulefile
        chmod a+x $rulefile
    fi
    exit 0
}

find_preferred() {
    local dev_type="$1"; shift
    local io_type="$1"; shift
    local exclude_pattern="$1"; shift
    local -n preferred_patterns=$1; shift
    local preferred_device=""
    local preferred_score=999
    while read device; do
        prefnum=0
        for prefname in "${preferred_patterns[@]}"; do
            if [[ "$device" =~ .*$prefname.* ]]; then
                if ((prefnum < preferred_score)); then
                    preferred_device="$device"
                    preferred_score=$prefnum
                fi
                break
            fi
        done
        if [ ! "$preferred_device" ]; then
            preferred_device="$device"
        fi
    done < <(pacmd list-${dev_type}s | grep "name:.*$io_type\\.usb" |
                 egrep -v "$exclude_pattern" | sed 's/.*<//g;s/>.*//g;')
    echo "$preferred_device"
}

get_default() {
    local dev_type="$1"; shift
    in_it="no"
    while read f1 f2 extra; do
        if [ "$f1" = "*" -a "$f2" = "index:" ]; then
            in_it="yes"
            continue
        fi
        if [ "$in_it" = "yes" ]; then
            if [ "$f1" = "index:" ]; then
                return
            fi
            if [ "$f1" = "name:" ]; then
                echo "$f2" | sed -n -e 's/^<\(.*\)>$/\1/p'
                return
            fi
        fi
    done < <(pacmd list-${dev_type}s)
}


lf=/tmp/usb-audio-select.$LOGNAME.pid

watch_screen_unlock() {
    echo $BASHPID >| $lf.$BASHPID
    if ! ln $lf.$BASHPID $lf; then
        if kill -0 $(cat $lf); then
            rm -f $lf.$BASHPID
            exit
        fi
        if ! ln -f $lf.$BASHPID $lf; then
            rm -f $lf.$BASHPID
            exit
        fi
    fi
    rm -f $lf.$BASHPID
    sleep 1
    if [ "$(cat $lf)" != "$BASHPID" ]; then
        exit
    fi
    gdbus monitor -y -d org.freedesktop.login1 |
        grep --line-buffered 'LockedHint.*false' |
        while read unlocked; do
            echo "$unlocked"
            configure_devices
        done
    rm -f $lf
}

kill_watcher() {
    pgid=$(ps -o 'pgid=' -p $(cat $lf))
    if [ -n "$pgid" ]; then
        kill -TERM -$pgid
    fi
}

configure_devices() {

    speaker=`find_preferred sink output "$SINK_EXCLUDE" PREFERRED_SINKS`
    mic=`find_preferred source input "$SOURCE_EXCLUDE" PREFERRED_SOURCES`

    switched="no"

    if [ "z$speaker" != "z" -a "$(get_default sink)" != "$speaker" ]
    then
        switched="yes"
        # use this speaker
        pacmd  set-default-sink "$speaker" | grep -vE 'Welcome|>>> $'
        # unmute
        pacmd  set-sink-mute "$speaker" 0 | grep -vE 'Welcome|>>> $'
        # Set the volume.  20000 is 20%
        pacmd  set-sink-volume "$speaker" 25000 | grep -vE 'Welcome|>>> $'
    fi

    if [ "z$mic" != "z" -a "$(get_default source)" != "$mic" ]
    then
        switched="yes"
        # use this microphone
        pacmd  set-default-source "$mic" | grep -vE 'Welcome|>>> $'
        # unmute
        pacmd  set-source-mute "$mic" 0 | grep -vE 'Welcome|>>> $'
        # Set the volume.  80000 is 80%
        pacmd  set-source-volume "$mic" 80000 | grep -vE 'Welcome|>>> $'
    fi

    if [ "$switched" = "yes" ]; then
        #play a sound to let you know that it was plugged in
        play /usr/share/sounds/speech-dispatcher/test.wav 2> /dev/null
    fi
}

if [ "$1" = "--install" ]
then
    install
fi

if [ ! -t 2 ]; then
    exec &>/tmp/usb-audio-select.$$.log
    set -vx
fi

if [ "$1" = "--kill" ]; then
    kill_watcher
    exit
fi

if [ "$1" = "--sleep" ]
then
    sleep 2
fi

if [ "$UID" == "0" ]
then
    # Check process table for users running PulseAudio
    for user in `ps axc -o user,command | grep pulseaudio | cut -f1 -d' ' | sort | uniq`
    do
        # Fork and relaunch this script as each pulseaudio user
        # tell it to sleep for a second to let pulseaudio install the usb device
        su $user -c "bash $0 --sleep" &
    done
else
    configure_devices
    (watch_screen_unlock&)
fi

exit 0
