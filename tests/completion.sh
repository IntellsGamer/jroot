#!/usr/bin/env bash
# tests/completion.sh - drive the generated bash completion the way bash does.
#
# 'jroot completion bash' parses its arguments out of COMP_LINE rather than
# COMP_WORDS, because ':' and '=' are in COMP_WORDBREAKS and would split
# "dev:/etc" into three words. That parsing, and the trimming that puts the
# replies back into the shape bash expects, is what this exercises: a completion
# script that loads cleanly but offers the wrong word is the failure mode worth
# catching, and 'bash -n' cannot see it.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
export JROOT_HOME="$root/.build/comphome"
fails=0

rm -rf "$JROOT_HOME"
mkdir -p "$JROOT_HOME/configs" "$JROOT_HOME/snapshots/dev" \
         "$JROOT_HOME/roots/dev/etc/nginx" "$JROOT_HOME/roots/dev/usr/local/bin" \
         "$JROOT_HOME/roots/dev/root" "$JROOT_HOME/roots/web/etc"
printf '%s\n' '{"name":"dev","image":"ubuntu:22.04","user":"root","ports":[3000,8080],"mounts":[["work","/tmp/w","ro"],["src","/tmp/s","rw"]]}' \
    > "$JROOT_HOME/configs/dev.json"
printf '%s\n' '{"name":"web","image":"ubuntu:24.04","user":"unroot","ports":[],"mounts":[]}' \
    > "$JROOT_HOME/configs/web.json"
: > "$JROOT_HOME/snapshots/dev/before-test.tar.gz"
: > "$JROOT_HOME/snapshots/dev/clean.tar.gz"
: > "$JROOT_HOME/roots/dev/root/app.tar.gz"

eval "$(bash "$root/jroot" completion bash)"

# COMP_WORDS[COMP_CWORD] is the text after the last COMP_WORDBREAKS character in
# the word being completed - that is what the replies have to line up with.
try() {
    local line="$1" want="$2" tail
    COMP_LINE="$line"
    COMP_POINT="${#line}"
    tail="${line##* }"
    case "$tail" in *[:=]*) tail="${tail##*[:=]}" ;; esac
    case "$line" in *' ') tail="" ;; esac
    COMP_WORDS=(jroot "$tail")
    COMP_CWORD=1
    COMPREPLY=()
    _jroot
    case " ${COMPREPLY[*]:-} " in
        *" $want "*) printf '  ok    %-42s -> %s\n' "$line|" "$want" ;;
        *) printf '  FAIL  %-42s -> wanted %s, got: %s\n' "$line|" "$want" "${COMPREPLY[*]:-(none)}"
           fails=$((fails + 1)) ;;
    esac
}

echo "commands"
try 'jroot '                          'completion'
try 'jroot com'                       'compare'
try 'jroot bui'                       'build'
echo "jail names"
try 'jroot enter '                    'dev'
try 'jroot enter d'                   'dev'
try 'jroot enter dev '                '--root'
try 'jroot which '                    'web'
try 'jroot clean dev '                'web'
try 'jroot compare dev '              'web'
echo "paths inside a jail"
try 'jroot file '                     'cp'
try 'jroot file cp '                  'dev:'
try 'jroot file cp dev:'              '/etc/'
try 'jroot file cp dev:/et'           '/etc/'
try 'jroot file cp dev:/etc/'         '/etc/nginx/'
try 'jroot file cp dev:/usr/'         '/usr/local/'
try 'jroot file cp dev:/root/a'       '/root/app.tar.gz'
try 'jroot file cp dev:/root/app.tar.gz web:/' '/etc/'
try 'jroot file mv dev ~/x :/ro'      '/root/'
echo "config-derived values"
try 'jroot revert '                   'snapshot'
try 'jroot revert snapshot dev '      'before-test'
try 'jroot rm-snapshot dev c'         'clean'
try 'jroot port dev '                 'list'
try 'jroot port dev rm '              '8080'
try 'jroot mnt dev '                  'work'
try 'jroot mnt dev set '              'src'
try 'jroot mnt dev set work '         'ro'
try 'jroot net set '                  'web'
try 'jroot net set web '              'auto'
echo "flags"
try 'jroot ssh dev '                  'status'
try 'jroot ssh dev start --'          '--random-password'
try 'jroot ssh dev start --p'         '--port='
try 'jroot init '                     'ubuntu:22.04'
try 'jroot init ubuntu:22.04 --u'     '--user=root'
try 'jroot list --'                   '--json'
try 'jroot history dev --l'           '--limit='
try 'jroot logs '                      'dev'
try 'jroot logs dev --l'               '--limit='
try 'jroot kill dev '                 '--force'
try 'jroot doctor --mute='            'forever'
try 'jroot doctor --'                 '--fix'
try 'jroot build --'                  '--build-arg='
try 'jroot build '                    '--tag='
try 'jroot completion '               'fish'
try 'jroot help '                     'ssh'
try 'jroot help lo'                    'logs'
try 'jroot help file '                'cp'

rm -rf "$JROOT_HOME"
echo
if [ "$fails" -eq 0 ]; then
    printf 'all completion checks passed\n'
else
    printf '%s completion check(s) failed\n' "$fails"
    exit 1
fi
