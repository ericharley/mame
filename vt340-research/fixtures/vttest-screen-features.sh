#!/bin/sh
# Reproduce the VTTEST 2.7 screen-feature transitions that stress scrolling,
# indexed clears, graphic rendition, and DECSC/DECRC.  Newlines deliberately
# remain LF here; the host PTY supplies its configured wire conversion.

set -eu

esc=$(printf '\033')

scroll_pass()
{
	label=$1
	first=$2
	last=$3
	direction=$4

	printf '%s[%s;%sr%s[2J' "$esc" "$first" "$last" "$esc"
	if [ "$direction" = down ]; then
		printf '%s[24A' "$esc"
	else
		printf '%s[24B' "$esc"
	fi
	i=1
	while [ "$i" -le 29 ]; do
		printf '%s scroll %s region [%s..%s] size %s Line %s\n' \
			"$label" "$direction" "$first" "$last" "$((last - first + 1))" "$i"
		if [ "$direction" = down ]; then
			printf '%sM%sM' "$esc" "$esc"
		fi
		i=$((i + 1))
	done
}

mode=${1:-all}

if [ "$mode" = cursor-one ]; then
	printf '%s[?6l%s[r%s[2J%s[10;12H*****%s7%s[1;1HA%s8*****%s[?25l' \
		"$esc" "$esc" "$esc" "$esc" "$esc" "$esc" "$esc" "$esc"
	exit 0
fi

if [ "$mode" = save-restore ]; then
	printf '%s[?6l%s[r%s[0m%s(B%s[2J' "$esc" "$esc" "$esc" "$esc" "$esc"
	printf '%s[8;12Hnormal%s[8;24Hbold%s[8;36Hunderscored%s[8;48Hblinking%s[8;60Hreversed' \
		"$esc" "$esc" "$esc" "$esc" "$esc"
	printf "%s[10;1Hstars:%s[12;1Hline:%s[14;1Hx'es:%s[16;1Hdiamonds:" \
		"$esc" "$esc" "$esc" "$esc"
	cset=0
	while [ "$cset" -le 3 ]; do
		case "$cset" in
		0) char='*'; charset='(B' ;;
		1) char='q'; charset='(0' ;;
		2) char='x'; charset='(B' ;;
		3) char=$(printf '\140'); charset='(0' ;;
		esac
		i=0
		while [ "$i" -le 4 ]; do
			case "$i" in
			0) attr=';0' ;;
			1) attr=';1' ;;
			2) attr=';4' ;;
			3) attr=';5' ;;
			4) attr=';7' ;;
			esac
			printf '%s[%s;%sH%s[%sm%s%s' "$esc" "$((10 + 2 * cset))" \
				"$((12 + 12 * i))" "$esc" "$attr" "$esc" "$charset"
			printf '%s%s%s%s%s' "$char" "$char" "$char" "$char" "$char"
			printf '%s7%s[%s;%sH%s[m%s(BA%s8' "$esc" "$esc" \
				"$((cset + 1))" "$((i + 1))" "$esc" "$esc" "$esc"
			printf '%s%s%s%s%s' "$char" "$char" "$char" "$char" "$char"
			i=$((i + 1))
		done
		cset=$((cset + 1))
	done
	printf '%s[0m%s(B%s[21;1HTest of the SAVE/RESTORE CURSOR feature. There should\n' "$esc" "$esc" "$esc"
	printf 'be ten characters of each flavour, and a rectangle\n'
	printf "of 5 x 4 A's filling the top left of the screen.%s[?25l" "$esc"
	exit 0
fi

if [ "$mode" = all ] || [ "$mode" = soft-small ]; then
	printf '%s[2J%s[?6h%s[?4h' "$esc" "$esc" "$esc"
	scroll_pass Soft 12 13 up
	scroll_pass Soft 12 13 down
fi
if [ "$mode" = all ] || [ "$mode" = soft-full ]; then
	printf '%s[?6h%s[?4h' "$esc" "$esc"
	scroll_pass Soft 1 24 up
	scroll_pass Soft 1 24 down
fi
if [ "$mode" = all ] || [ "$mode" = jump-small ]; then
	printf '%s[?6h%s[?4l' "$esc" "$esc"
	scroll_pass Jump 12 13 up
	scroll_pass Jump 12 13 down
fi
if [ "$mode" = all ] || [ "$mode" = jump-full ]; then
	printf '%s[?6h%s[?4l' "$esc" "$esc"
	scroll_pass Jump 1 24 up
	scroll_pass Jump 1 24 down
fi

# Restore the normal viewport, clear, and draw the first VTTEST rendition
# page.  Surviving scroll text on this page is a failure.
if [ "$mode" != all ] && [ "$mode" != rendition ]; then
	exit 0
fi

printf '%s[r%s[?6l%s[2J' "$esc" "$esc" "$esc"
printf '%s[1;20HGraphic rendition test pattern:' "$esc"
printf '%s[4;1H%s[0mvanilla' "$esc" "$esc"
printf '%s[4;40H%s[0;1mbold' "$esc" "$esc"
printf '%s[6;6H%s[;4munderline' "$esc" "$esc"
printf '%s[6;45H%s[;1m%s[4mbold underline' "$esc" "$esc" "$esc"
printf '%s[8;1H%s[0;5mblink' "$esc" "$esc"
printf '%s[8;40H%s[0;5;1mbold blink' "$esc" "$esc"
printf '%s[10;6H%s[0;4;5munderline blink' "$esc" "$esc"
printf '%s[10;45H%s[0;1;4;5mbold underline blink' "$esc" "$esc"
printf '%s[12;1H%s[1;4;5;0;7mnegative' "$esc" "$esc"
printf '%s[12;40H%s[0;1;7mbold negative' "$esc" "$esc"
printf '%s[14;6H%s[0;4;7munderline negative' "$esc" "$esc"
printf '%s[14;45H%s[0;1;4;7mbold underline negative' "$esc" "$esc"
printf '%s[16;1H%s[1;4;;5;7mblink negative' "$esc" "$esc"
printf '%s[16;40H%s[0;1;5;7mbold blink negative' "$esc" "$esc"
printf '%s[18;6H%s[0;4;5;7munderline blink negative' "$esc" "$esc"
printf '%s[18;45H%s[0;1;4;5;7mbold underline blink negative' "$esc" "$esc"
printf '%s[m%s[?5l%s[23;1H%s[0KDark background. Push <RETURN>%s[?25l' \
	"$esc" "$esc" "$esc" "$esc" "$esc"
