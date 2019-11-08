#!/bin/sh
user=logger
exec >/dev/null 2>&1
service="${PWD%/log}"
service="${service##*/}"
logdir="/var/log/service/$service"
mkdir -p "$logdir"
chown -R "$user": "$logdir"
chmod -R go-rwxst,u+rwX "$logdir"
rm logdir
ln -s "$logdir" logdir
chmod a+rX .
args=""
test "$LOG_NOTIMESTAMP" || args="-tt"
exec \
env - PATH="$PATH" \
chpst -u "$user" -m $((20 * 1024*1024)) \
svlogd $args "$logdir"

