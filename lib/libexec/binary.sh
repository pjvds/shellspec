#shellcheck shell=sh disable=SC2004

# busybox 1.1.3: `-A n`, `-t o1` not supported
# busybox 1.10.2: `od -b` not working properly
if od -t o1 -v /dev/null >/dev/null 2>&1; then
  od_command() { od -t o1 -v; }
else
  if [ $? -eq 127 ] && hexdump /dev/null >/dev/null 2>&1; then
    od_command() { hexdump -b -v; }
  else
    od_command() { od -b -v; }
  fi
fi

octal_dump() {
  od_command | (
    while IFS= read -r line; do
      eval "set -- $line"
      [ $# -gt 1 ] || continue
      shift
      while [ $# -gt 0 ]; do echo "$1" && shift; done
    done
  ) &&:
}
