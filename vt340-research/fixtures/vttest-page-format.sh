#!/bin/sh
# Reproduce the core of VTTEST 11.2.3 without its menus or interactive holds.

set -eu

esc=$(printf '\033')
mode=${1:-${VT340_PAGE_FORMAT_MODE:-align}}

printf '%s[?25l%s[2J' "$esc" "$esc"
if [ "$mode" != text ] && [ "$mode" != clear ]; then
	printf '%s#8' "$esc"
fi

case "$mode" in
clear)
	;;
align)
	;;
text)
	printf '%s[H' "$esc"
	printf 'EEEEEEEE'
	;;
columns-80)
	printf '%s[80$|' "$esc"
	;;
columns-80-message)
	printf '%s[80$|%s[20;1HPAGE FORMAT TEST' "$esc" "$esc"
	;;
columns-132)
	printf '%s[132$|' "$esc"
	;;
lines-24)
	printf '%s[24t' "$esc"
	;;
lines-36)
	printf '%s[36t' "$esc"
	;;
lines-36-message)
	printf '%s[36t%s[20;1HPAGE FORMAT TEST' "$esc" "$esc"
	;;
lines-72)
	printf '%s[72t' "$esc"
	;;
lines-144)
	printf '%s[144t' "$esc"
	;;
*)
	echo "usage: $0 clear|align|text|columns-80|columns-80-message|columns-132|lines-24|lines-36|lines-36-message|lines-72|lines-144" >&2
	exit 2
	;;
esac
