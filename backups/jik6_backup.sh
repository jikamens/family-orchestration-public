#!/bin/bash -e

TD=/d/backup/jik5

nflag=
vflag=

while [ "$1" ]; do
    case "$1" in
        -n|--dryrun|--dry-run) shift; nflag=--dry-run ;;
        -v|--verbose) shift; vflag=--verbose ;;
        *) echo "Bad argument: $1" 1>&2; exit 1 ;;
    esac
done

rsync="rsync -azx $nflag $vflag --delete --delete-excluded"

home_mounts="$(awk '{print $2}' /proc/mounts | grep ^/home/jik/)"

$rsync \
      --exclude '#*#' \
      --exclude '**/GPUCache' \
      --exclude '**/ImapMail' \
      --exclude '*~' \
      --exclude '.#*' \
      --exclude '/.SynologyDrive' \
      --exclude '/.ansible' \
      --exclude '/.cache' \
      --exclude '/.ccache' \
      --exclude '/.config/**.log' \
      --exclude '/.config/Slack' \
      --exclude '/.config/google-chrome' \
      --exclude '/.config/libreoffice' \
      --exclude '/.dropbox*' \
      --exclude '/.gem' \
      --exclude '/.digikam' \
      --exclude '/.local/lib' \
      --exclude '/.local/share/GottCode' \
      --exclude '/.local/share/Trash' \
      --exclude '/.local/share/app-info' \
      --exclude '/.local/share/digikam' \
      --exclude '/.local/share/firefoxpwa' \
      --exclude '/.local/share/gvfs-metadata' \
      --exclude '/.local/share/heroku' \
      --exclude '/.local/share/icons' \
      --exclude '/.local/share/keybase' \
      --exclude '/.local/share/mime' \
      --exclude '/.local/share/rhythmbox' \
      --exclude '/.local/share/teamviewer*' \
      --exclude '/.local/share/torbrowser' \
      --exclude '/.local/share/tracker' \
      --exclude '/.local/share/virtualenv' \
      --exclude '/.local/share/zeitgeist' \
      --exclude '/.local/state' \
      --exclude '/.macromedia' \
      --exclude '/.mozbuild' \
      --exclude '/.mozilla' \
      --exclude '/.npm' \
      --exclude '/.nv' \
      --exclude '/.thunderbird/**.sqlite*' \
      --exclude '/.thunderbird/**/Photos' \
      --exclude '/.thunderbird/**/cache' \
      --exclude '/.thunderbird/**/photos' \
      --exclude '/.thunderbird/*/TestPilotErrorLog.log' \
      --exclude '/.thunderbird/*/blocklist.xml' \
      --exclude '/.thunderbird/*/blocklists' \
      --exclude '/.thunderbird/*/cert8.db' \
      --exclude '/.thunderbird/*/cert9.db' \
      --exclude '/.thunderbird/*/crashes' \
      --exclude '/.thunderbird/*/chrome_debugger_profile' \
      --exclude '/.thunderbird/*/extensions' \
      --exclude '/.thunderbird/*/gcontactsync' \
      --exclude '/.thunderbird/*/gcontactsync' \
      --exclude '/.thunderbird/*/key4.db' \
      --exclude '/.thunderbird/*/pepmda' \
      --exclude '/.thunderbird/*/saved-telemetry-pings' \
      --exclude '/.thunderbird/*/security_state' \
      --exclude '/.thunderbird/*/training.dat' \
      --exclude '/.thunderbird/*/xulstore' \
      --exclude '/.thunderbird/Crash Reports' \
      --exclude '/.virtualenvs' \
      --exclude '/.wine' \
      --exclude '/.zoom' \
      --exclude '/Applications' \
      --exclude '/CloudStation/gnucash/*.LCK*' \
      --exclude '/CloudStation/gnucash/*.gnucash' \
      --exclude '/CloudStation/gnucash/*.log' \
      --exclude '/Dropbox/.dropbox.cache' \
      --exclude '/Mail/Archives/mairix' \
      --exclude '/Mail/Archives/mfolder*' \
      --exclude '/build' \
      --exclude '/closed/toodledo_backup/*.bak' \
      --exclude '/closed/toodledo_backup/backup-*.diff' \
      --exclude '/scripts' \
      --exclude '/src/*/.tox' \
      --exclude '/src/*/send-later' \
      --exclude '/src/linkedin-job-filterer/.chrome' \
      --exclude '/snap' \
      --exclude '/tmp' \
      --exclude-from <(echo "$home_mounts" | sed 's,^/home/jik,,') \
      --exclude-from <(find /home/jik -xdev \( -path '*/.local/share/keybase' -prune \) -o \( -name core -o -name 'core.[0-9]*' \) -type f -print 2> >(grep -v -f <(echo "$home_mounts" | sed 's,\(.*\),^find: .\1.: Permission denied,') 1>&2) | sed 's,/home/jik,,') \
      /home/jik/ $TD/home/jik/

$rsync \
      --exclude '/diagnostic.data' \
      --exclude '/journal' \
      /var/lib/mongodb/ $TD/var/lib/mongodb/


for dir in var/spool/cron var/lib/mysql \
           d/mysql/backups:var/lib/mysql-backups \
           d/mongodb/incremental-export:var/lib/mongo-incremental-export; do
    case $dir in
        *:*) sd=${dir%:*}
             td=${dir#*:}
             ;;
        *) sd=$dir
           td=$dir
           ;;
    esac
    $rsync /$sd/ $TD/$td/
done
