#!/bin/sh
# Source this file from a shell attached to the VT340 Comm 1 PTY:
#
#   . /path/to/mame/vt340-research/tools/vt340-shell-compat.sh
#
# It advertises the VT340 capability set needed by graphics-aware software.
# Override that for a deliberately conservative VT100 session with:
#
#   VT340_TERM=vt100 . /path/to/vt340-shell-compat.sh

VT340_ROWS=${VT340_ROWS:-24}
VT340_COLUMNS=${VT340_COLUMNS:-80}

# TERM describes the behavior applications may use, including ReGIS and SIXEL
# capabilities that are specific to this terminal family.
TERM=${VT340_TERM:-vt340}
export TERM

# Keep command output within the terminal's presently reliable character set.
# Individual Unicode experiments can override these after sourcing the file.
LANG=C
LC_ALL=C
export LANG LC_ALL

# Do not let common tools infer color or hyperlinks from the host terminal.
NO_COLOR=1
export NO_COLOR
unset COLORTERM CLICOLOR CLICOLOR_FORCE LSCOLORS LS_COLORS

# Avoid alternate-screen, color, and cursor-control sequences from pagers while
# the terminal emulation is being tested.  Users can run less explicitly when
# testing those features.
PAGER=cat
MANPAGER=cat
GIT_PAGER=cat
SYSTEMD_PAGER=cat
export PAGER MANPAGER GIT_PAGER SYSTEMD_PAGER

if [ -t 0 ]; then
	# Save the original line discipline so it can be restored without logging
	# out.  A new getty session will establish its own settings in any case.
	VT340_SAVED_STTY=$(stty -g 2>/dev/null) || VT340_SAVED_STTY=
	export VT340_SAVED_STTY

	# The VT340 Comm 1 defaults are 19200 baud, 8 data bits, no parity, one stop
	# bit, with XON/XOFF output pacing. A PTY does not model the baud clock, but
	# IXON lets the terminal pause a sustained SIXEL stream before its UART/parser
	# queues overflow. IXOFF remains disabled because the host shell does not need
	# the kernel to generate flow-control bytes on the terminal's behalf.
	# Preserve horizontal-tab controls for the terminal itself.  macOS can
	# otherwise enable OXTABS and replace HT with spaces before VTTEST or other
	# applications reach Comm 1; double-width lines then use the wrong cursor
	# position because their tab-and-backup alignment sequence is destroyed.
	stty sane 19200 cs8 -parenb -cstopb -istrip ixon -ixoff -oxtabs \
		icrnl -inlcr -igncr opost onlcr \
		echo echoe echok icanon isig iexten \
		rows "$VT340_ROWS" columns "$VT340_COLUMNS"
fi

# Remove frequently inherited aliases that force ANSI color independently of
# TERM.  The errors are suppressed because most login shells define none of
# them.
unalias ls grep egrep fgrep diff 2>/dev/null || :

# Use an unadorned, single-line prompt and disable shell-generated bracketed
# paste control sequences.  Keep this section harmless in plain POSIX shells.
unset PROMPT_COMMAND RPROMPT
if [ -n "${ZSH_VERSION:-}" ]; then
	PROMPT='%n@%m:%1~%# '
	PS1=$PROMPT
	unset zle_bracketed_paste
elif [ -n "${BASH_VERSION:-}" ]; then
	PS1='\u@\h:\W\$ '
	bind 'set enable-bracketed-paste off' >/dev/null 2>&1 || :
else
	PS1='$ '
fi
export PS1

# Restore only the saved tty line discipline.  Environment and prompt changes
# naturally disappear on logout; they can also be overridden normally.
vt340_restore_tty()
{
	if [ -n "${VT340_SAVED_STTY:-}" ] && [ -t 0 ]; then
		stty "$VT340_SAVED_STTY"
	else
		printf '%s\n' 'No saved VT340 tty state is available.' >&2
		return 1
	fi
}

printf 'VT340 shell compatibility enabled: TERM=%s, %sx%s, ASCII locale, XON/XOFF pacing, tabs preserved.\n' \
	"$TERM" "$VT340_COLUMNS" "$VT340_ROWS"
