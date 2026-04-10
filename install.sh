#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
global_target="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"

mode="copy"
project_root=""
skills_arg=""
list_only=0

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [--skills skill1,skill2] [--project /path/to/project] [--mode copy|symlink]
  ./install.sh --list
  ./install.sh --help

Options:
  --skills   Comma-separated skill names to install. Defaults to all skills.
  --project  Install into <project>/.opencode/skills instead of the global OpenCode skills directory.
  --mode     Install mode: copy (default) or symlink.
  --list     Print discovered skills and exit.
  --help     Show this help message.

Examples:
  ./install.sh
  ./install.sh --skills flutter-github-deploy
  ./install.sh --project /path/to/project
  ./install.sh --skills flutter-github-deploy --project /path/to/project --mode symlink
EOF
}

trim() {
  printf '%s' "$1" | xargs
}

declare -A skill_paths=()
declare -a skill_names=()

discover_skills() {
  local skill_file skill_dir skill_name

  while IFS= read -r skill_file; do
    skill_dir="$(dirname "$skill_file")"
    skill_name="$(basename "$skill_dir")"

    if [[ -v "skill_paths[$skill_name]" ]]; then
      printf 'Duplicate skill name detected: %s\n' "$skill_name" >&2
      printf ' - %s\n' "${skill_paths[$skill_name]}" >&2
      printf ' - %s\n' "$skill_dir" >&2
      exit 1
    fi

    skill_paths["$skill_name"]="$skill_dir"
    skill_names+=("$skill_name")
  done < <(find "$repo_root" -path '*/.git' -prune -o -name 'SKILL.md' -type f -print | sort)

  if [[ ${#skill_names[@]} -eq 0 ]]; then
    printf 'No skills found in %s\n' "$repo_root" >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skills)
        [[ $# -ge 2 ]] || { printf 'Missing value for --skills\n' >&2; exit 1; }
        skills_arg="$2"
        shift 2
        ;;
      --project)
        [[ $# -ge 2 ]] || { printf 'Missing value for --project\n' >&2; exit 1; }
        project_root="$2"
        shift 2
        ;;
      --mode)
        [[ $# -ge 2 ]] || { printf 'Missing value for --mode\n' >&2; exit 1; }
        mode="$2"
        shift 2
        ;;
      --list)
        list_only=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown argument: %s\n\n' "$1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

validate_mode() {
  case "$mode" in
    copy|symlink) ;;
    *)
      printf 'Invalid mode: %s\n' "$mode" >&2
      printf 'Expected one of: copy, symlink\n' >&2
      exit 1
      ;;
  esac
}

print_skills() {
  local skill_name
  for skill_name in "${skill_names[@]}"; do
    printf '%s\n' "$skill_name"
  done
}

select_skills() {
  local raw_name skill_name

  if [[ -z "$skills_arg" ]]; then
    printf '%s\n' "${skill_names[@]}"
    return
  fi

  IFS=',' read -r -a requested_skills <<< "$skills_arg"
  for raw_name in "${requested_skills[@]}"; do
    skill_name="$(trim "$raw_name")"

    if [[ -z "$skill_name" ]]; then
      continue
    fi

    if [[ ! -v "skill_paths[$skill_name]" ]]; then
      printf 'Unknown skill: %s\n' "$skill_name" >&2
      printf 'Available skills:\n' >&2
      print_skills >&2
      exit 1
    fi

    printf '%s\n' "$skill_name"
  done
}

resolve_target_dir() {
  if [[ -n "$project_root" ]]; then
    if [[ ! -d "$project_root" ]]; then
      printf 'Project directory does not exist: %s\n' "$project_root" >&2
      exit 1
    fi

    printf '%s/.opencode/skills\n' "$project_root"
  else
    printf '%s\n' "$global_target"
  fi
}

install_skill() {
  local skill_name="$1"
  local target_dir="$2"
  local src_dir dest_dir

  src_dir="${skill_paths[$skill_name]}"
  dest_dir="$target_dir/$skill_name"

  rm -rf "$dest_dir"

  if [[ "$mode" == "copy" ]]; then
    cp -a "$src_dir" "$dest_dir"
  else
    ln -s "$src_dir" "$dest_dir"
  fi
}

main() {
  local target_dir skill_name
  local -a selected_skills=()

  parse_args "$@"
  discover_skills
  validate_mode

  if [[ $list_only -eq 1 ]]; then
    print_skills
    exit 0
  fi

  mapfile -t selected_skills < <(select_skills)
  if [[ ${#selected_skills[@]} -eq 0 ]]; then
    printf 'No skills selected for installation\n' >&2
    exit 1
  fi

  target_dir="$(resolve_target_dir)"
  mkdir -p "$target_dir"

  for skill_name in "${selected_skills[@]}"; do
    install_skill "$skill_name" "$target_dir"
  done

  printf 'Installed %d skill(s) to %s using %s mode:\n' "${#selected_skills[@]}" "$target_dir" "$mode"
  for skill_name in "${selected_skills[@]}"; do
    printf ' - %s\n' "$skill_name"
  done
}

main "$@"
