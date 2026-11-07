#!/bin/sh
# Reproduce VTTEST's final double-size character pattern without its menus.

set -eu

esc=$(printf '\033')

# Reset margins and attributes, clear the screen, and establish VTTEST's
# eight-column tab stops.  The frame uses G0 and G1 DEC Special Graphics in
# the same sequence as tst_doublesize().
printf '%s[r%s[?6l%s[0m%s(B%s[2J%s[3g' \
	"$esc" "$esc" "$esc" "$esc" "$esc" "$esc"
printf '%s[?3h%s[1;1H%s[3g' "$esc" "$esc" "$esc"
printf '%s[1;1H' "$esc"
col=1
while [ "$col" -le 132 ]; do
	printf '%s[8C%sH' "$esc" "$esc"
	col=$((col + 8))
done
printf '%s[?3l%s[2J' "$esc" "$esc"

printf '%s[8;1H%s#3%s(0lqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqk' "$esc" "$esc" "$esc"
printf '%s[9;1H%s#4lqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqk' "$esc" "$esc"
printf '%s[10;1H%s#3x\t\t\t\t\tx' "$esc" "$esc"
printf '%s[11;1H%s#4x\t\t\t\t\tx' "$esc" "$esc"
printf '%s[12;1H%s#3x\t\t\t\t\tx' "$esc" "$esc"
printf '%s[13;1H%s#4x\t\t\t\t\tx' "$esc" "$esc"
printf '%s)0%s[14;1H%s#3x                                      x' "$esc" "$esc" "$esc"
printf '%s[15;1H%s#4x                                      x' "$esc" "$esc"
printf '%s[16;1H%s#3mqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqj' "$esc" "$esc"
printf '%s[17;1H%s#4mqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqj' "$esc" "$esc"

printf '%s(B%s[1;5m%s[12;3H* The mad programmer strikes again * ' "$esc" "$esc" "$esc"
printf '%s[13;3H\t%s[6D* The mad programmer strikes again *' "$esc" "$esc"
printf '%s[0m%s[21;1HAnother test pattern...  a frame with blinking bold text,' "$esc" "$esc"
printf '%s[22;1Hall in double-height double-width size.%s[?25l' "$esc" "$esc"
