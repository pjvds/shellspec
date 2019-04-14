#shellcheck shell=sh disable=SC2004,SC2119,SC2120

# shellcheck source=lib/libexec.sh
. "${SHELLSPEC_LIB:-./lib}/libexec.sh"
use constants trim
load parser

initialize() {
  lineno=0 block_no=0 block_no_stack='' example_no=0 skip_id=0 error=''
}

finalize() {
  [ "$block_no_stack" ] || return 0
  syntax_error "unexpected end of file (expecting 'End')"
  lineno=
  while [ "$block_no_stack" ]; do block_end ""; done
}

initialize_id() {
  id='' id_state='begin'
}

increasese_id() {
  if [ "$id_state" = "begin" ]; then
    id=$id${id:+:}1
  else
    id_state="begin"
    case $id in
      *:*) id="${id%:*}:$((${id##*:} + 1))" ;;
      *) id=$(($id + 1)) ;;
    esac
  fi
}

decrease_id() {
  [ "$id_state" = "end" ] && id=${id%:*}
  id_state="end"
}

one_line_syntax_check() { :; }

is_constant_name() {
  case $1 in ([!A-Z_]*) return 1; esac
  case $1 in (*[!A-Z0-9_]*) return 1; esac
}

is_function_name() {
  case $1 in ([!a-zA-Z_]*) return 1; esac
  case $1 in (*[!a-zA-Z0-9_]*) return 1; esac
}

block_example_group() {
  if [ "$inside_of_example" ]; then
    syntax_error "Describe/Context cannot be defined inside of Example"
    return 0
  fi

  if ! one_line_syntax_check error ": $1"; then
    syntax_error "Describe/Context has occurred an error" "$error"
    return 0
  fi

  increasese_id
  block_no=$(($block_no + 1))
  eval trans block_example_group ${1+'"$@"'}
  block_no_stack="$block_no_stack $block_no"
}

block_example() {
  if [ "$inside_of_example" ]; then
    syntax_error "It/Example/Specify/Todo cannot be defined inside of Example"
    return 0
  fi

  if ! one_line_syntax_check error ": $1"; then
    syntax_error "It/Example/Specify/Todo has occurred an error" "$error"
    return 0
  fi

  increasese_id
  block_no=$(($block_no + 1)) example_no=$(($example_no + 1))
  eval trans block_example ${1+'"$@"'}
  block_no_stack="$block_no_stack $block_no"
  inside_of_example="yes"
}

block_end() {
  if [ -z "$block_no_stack" ]; then
    syntax_error "unexpected 'End'"
    return 0
  fi

  decrease_id
  eval trans block_end ${1+'"$@"'}
  block_no_stack="${block_no_stack% *}"
  inside_of_example=""
}

x() { "$@"; skip; }

todo() {
  block_example "$1"
  block_end ""
}

statement() {
  if [ -z "$inside_of_example" ]; then
    syntax_error "When/The cannot be defined outside of Example"
    return 0
  fi
  eval trans statement ${1+'"$@"'}
}

control() {
  case $1 in (before|after)
    if [ "$inside_of_example" ]; then
      syntax_error "Before/After cannot be defined inside of Example"
      return 0
    fi
  esac
  eval trans control ${1+'"$@"'}
}

skip() {
  skip_id=$(($skip_id + 1))
  eval trans skip ${1+'"$@"'}
}

data() {
  data_line=${2:-}
  trim data_line

  eval trans data_begin ${1+'"$@"'}
  case $data_line in
    '' | '#'* | '|'*)
      trans data_here_begin "$1" "$data_line"
      while IFS= read -r line || [ "$line" ]; do
        lineno=$(($lineno + 1))
        trim line
        case $line in
          '#|'*) trans data_here_line "$line" ;;
          '#'*) ;;
          End | End\ * ) break ;;
          *) syntax_error "Data texts should begin with '#|'"; break ;;
        esac
      done
      trans data_here_end ;;
    "'"* | '"'*) trans data_text "$data_line" ;;
    *) trans data_func "$data_line" ;;
  esac
  eval trans data_end ${1+'"$@"'}
}

text_begin() {
  eval trans text_begin ${1+'"$@"'}
  inside_of_text=1
}

text() {
  case $1 in
    '#|'*) eval trans text ${1+'"$@"'}; return 0 ;;
    *) text_end; return 1 ;;
  esac
}

text_end() {
  eval trans text_end ${1+'"$@"'}
  inside_of_text=''
}

constant() {
  if [ "$block_no_stack" ]; then
    syntax_error "Constant should be defined outside of Example Group/Example"
    return 0
  fi

  line=$1
  trim line
  name=${line%%:*} value=${line#*:}
  trim value
  if is_constant_name "$name"; then
    trans constant "$name" "$value"
  else
    syntax_error "Constant name should match pattern [A-Z_][A-Z0-9_]*"
  fi
}

define() {
  line=$1
  trim line
  name="${line%% *}"
  case $line in (*" "*) value="${line#* }" ;; (*) value= ;; esac

  if ! one_line_syntax_check error ": $1"; then
    syntax_error "Def has occurred an error" "$error"
    return 0
  fi

  if is_function_name "$name"; then
    trans define "$name" "$value"
  else
    syntax_error "Def name should match pattern [a-zA-Z_][a-zA-Z0-9_]*"
  fi
}

include() {
  if [ "$inside_of_example" ]; then
    syntax_error "Include cannot be defined inside of Example"
    return 0
  fi

  if ! one_line_syntax_check error ": $1"; then
    syntax_error "Include has occurred an error" "$error"
    return 0
  fi

  eval trans include ${1+'"$@"'}
}

error() {
  syntax_error "${*:-}"
}

translate() {
  initialize_id
  inside_of_example='' inside_of_text=''
  while IFS= read -r line || [ "$line" ]; do
    lineno=$(($lineno + 1)) work=$line
    trim work

    [ "$inside_of_text" ] && text "$work" && continue

    dsl=${work%% *}
    dsl_mapping "$dsl" "${work#$dsl}" || trans line "$line"
  done
}
