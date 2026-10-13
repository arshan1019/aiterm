/// /etc/profile.d/aiterm.sh, written into the guest at every session start.
///
/// Shell integration as VS Code, iTerm2 and WezTerm do it: at each prompt
/// the shell reports the last exit status, the current folder and a prompt
/// mark (OSC 133;D / OSC 7 / OSC 133;A). The app uses these to follow the
/// folder (restoring tabs where they were) and to notice when a command
/// finishes. Nothing is printed for non-interactive shells.
///
/// bash/zsh-only syntax is kept inside `eval` so busybox ash, which parses
/// the whole file, never sees it.
const shellProfile = r'''# aiterm shell integration (OSC 7 / OSC 133). Managed by the app.
case $- in *i*) ;; *) return 0 ;; esac
[ -n "$AITERM_SHELL_INTEGRATION" ] && return 0
AITERM_SHELL_INTEGRATION=1

__aiterm_prompt() {
	printf '\033]133;D;%s\007\033]7;file://localhost%s\007\033]133;A\007' "$1" "$PWD"
}

if [ -n "$BASH_VERSION" ]; then
	eval 'PROMPT_COMMAND="__aiterm_prompt \$?${PROMPT_COMMAND:+; $PROMPT_COMMAND}"; PS0=$'"'"'\e]133;C\a'"'"
elif [ -n "$ZSH_VERSION" ]; then
	eval '__aiterm_precmd() { __aiterm_prompt $?; }
		__aiterm_preexec() { printf "\033]133;C\007"; }
		precmd_functions+=(__aiterm_precmd); preexec_functions+=(__aiterm_preexec)'
else
	# busybox ash expands $(...) in PS1 each time; \[ \] keeps the codes out
	# of the prompt width so line editing stays aligned.
	PS1='\[$(__aiterm_prompt $?)\]'"$PS1"
fi
''';
