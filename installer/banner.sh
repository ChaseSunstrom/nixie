# shellcheck shell=bash
f=/var/lib/nixie/setup/banner.txt; last=""
while :; do
  now=$(@coreutils@/bin/stat -c %Y "$f" 2>/dev/null || echo none)
  if [ "$now" != "$last" ]; then
    last=$now
    printf '\033[2J\033[H'
    @coreutils@/bin/cat "$f" 2>/dev/null || printf '\n  Starting the setup service...\n'
    printf '\n  Terminal wizard: press Alt+F2.\n'
  fi
  @coreutils@/bin/sleep 2
done
