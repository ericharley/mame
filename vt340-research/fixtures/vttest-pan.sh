#!/bin/sh
# Exercise VT340 panning, or reproduce VTTEST 11.2.2's incompatible generic
# scroll test.  On a VT340, SU/SD move the user window over unchanged page
# memory; they do not turn diagonal characters into a horizontal row.

set -eu

esc=$(printf '\033')
mode=${1:-${VT340_PAN_MODE:-pan-down}}

case "$mode" in
pan-down|pan-up|vttest-su|vttest-sd) ;;
*) echo "usage: $0 pan-down|pan-up|vttest-su|vttest-sd" >&2; exit 2 ;;
esac

printf '%s[?6l%s[r%s[?4l%s[?25l' "$esc" "$esc" "$esc" "$esc"

case "$mode" in
pan-down|pan-up)
	# A 72-line page makes vertical panning meaningful.  Uncouple the cursor so
	# writing the off-screen row 25 does not move the user window implicitly.
	printf '%s[72t%s[?61l%s[2J' "$esc" "$esc" "$esc"
	n=1
	while [ "$n" -le 25 ]; do
		printf '%s[%s;1HPAGE ROW %02d' "$esc" "$n" "$n"
		n=$((n + 1))
	done
	printf '%s[1;1H' "$esc"
	if [ "$mode" = pan-down ]; then
		printf '%s[S' "$esc"
	else
		# Establish room above the window before testing Pan Up.
		printf '%s[S%s[T' "$esc" "$esc"
	fi
	exit 0
	;;
esac

printf '%s[2J' "$esc"

n=1
while [ "$n" -le 20 ]; do
	if [ "$mode" = vttest-su ]; then
		row=$((22 - n))
		final=S
	else
		row=$n
		final=T
	fi
	printf '%s[%s;%sH*' "$esc" "$row" "$n"
	case $((n % 3)) in
	0) printf '%s[%s' "$esc" "$final" ;;
	1) printf '%s[0%s' "$esc" "$final" ;;
	2) printf '%s[1%s' "$esc" "$final" ;;
	esac
	n=$((n + 1))
done
