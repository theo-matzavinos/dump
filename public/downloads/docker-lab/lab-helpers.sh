# Helpers for the "Docker behind the scenes" lab: bash on Linux, macOS and WSL.
#
# Load it into your current bash session (don't run it as a program):
#
#   source ./lab-helpers.sh
#
# Loading it:
#   - creates a new lab directory with a random name under your temporary
#     directory and moves your shell into it;
#   - checks that Docker answers, that the web port is free, and that nothing
#     in Docker already uses the lab's random name;
#   - sets $lab, $lab_dir, $lab_share and $lab_user for the article's commands,
#     and exports COMPOSE_PROJECT_NAME and WEB_PORT for Docker Compose.
#
# The article's docker commands add --label "docker-lab=$lab" to the containers
# and images they create, and compose.yaml adds the same label to its images.
#
# When you're done, run lab_cleanup. It first lists and checks everything it
# will remove: the experiment containers and the exact image tags the article
# creates (each must carry the lab's label), plus the containers, network and
# volume of the lab's Compose project (each must have the expected name). If a
# check fails, or Docker reports an error while checking, it stops before
# deleting anything. Then it removes that list and the lab directory. If Docker
# fails partway through, what's already removed can't be restored; fix the
# error and run lab_cleanup again.
#
# Cleanup leaves untagged images alone. Rebuilding a tag leaves the older image
# without a name, but a label alone can't show whether the lab built it or
# another image was built FROM a lab image and inherited the label.
#
# The script needs bash 3.2 or newer. On macOS, whose default shell is zsh,
# start bash first by typing: bash

# The article's commands use $lab_share and $lab_user.
# shellcheck disable=SC2034

if [ -z "${BASH_VERSION:-}" ]; then
  echo "lab: load this file from bash. Type 'bash', then source it again." >&2
  # shellcheck disable=SC2317 # 'exit' runs only when the file isn't sourced.
  return 1 2>/dev/null || exit 1
fi

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "lab: load this file with 'source ./lab-helpers.sh' instead of running it." >&2
  exit 1
fi

lab_fail() {
  echo "lab: $1" >&2
  return 1
}

# Prints the ID of every resource of one kind (container, network, volume)
# that Docker Compose created for this lab's project.
lab_project_ids() {
  local kind=$1
  local ids

  if [ "$kind" = "container" ]; then
    ids=$(docker container ls --all --quiet --filter "label=com.docker.compose.project=$lab") || return 1
  else
    ids=$(docker "$kind" ls --quiet --filter "label=com.docker.compose.project=$lab") || return 1
  fi
  printf '%s\n' "$ids"
}

# Prints the name of one resource that a list command just returned.
lab_resource_name() {
  local kind=$1
  local id=$2

  docker "$kind" inspect --format '{{.Name}}' "$id"
}

lab_setup() {
  local port=${WEB_PORT:-8080}
  local name random temp_root dir found

  if [ -n "${lab:-}" ]; then
    lab_fail "this shell already has a lab ($lab). Run lab_cleanup or open a new terminal." || return 1
  fi

  docker version >/dev/null || lab_fail "Docker didn't answer. Start Docker and try again." || return 1
  docker compose version >/dev/null || lab_fail "Docker Compose isn't available." || return 1

  case $port in
    '' | *[!0-9]*) lab_fail "WEB_PORT must be a number." || return 1 ;;
  esac
  if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
    lab_fail "choose a WEB_PORT between 1024 and 65535." || return 1
  fi
  # Opening a connection succeeds only if something already listens there.
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    lab_fail "port $port is in use. Run 'export WEB_PORT=8081' (or another free port) and source this file again." || return 1
  fi

  random=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n') || return 1
  name="dockerscenes-$random"

  # Docker's name filters match parts of names, so this also catches
  # "$name-web-1", "${name}_dbdata" and the like.
  found=$(docker container ls --all --quiet --filter "name=$name") || return 1
  found="$found$(docker container ls --all --quiet --filter "label=com.docker.compose.project=$name")" || return 1
  found="$found$(docker network ls --quiet --filter "name=$name")" || return 1
  found="$found$(docker volume ls --quiet --filter "name=$name")" || return 1
  found="$found$(docker image ls --quiet --filter "reference=$name-*")" || return 1
  if [ -n "$found" ]; then
    lab_fail "Docker already has resources named $name. Source this file again to pick a new name." || return 1
  fi

  temp_root=${TMPDIR:-/tmp}
  dir="${temp_root%/}/$name"
  mkdir "$dir" || return 1
  mkdir "$dir/layers" "$dir/api" "$dir/share" || return 1
  printf '%s\n' "$name" >"$dir/.lab-owner" || return 1
  cd "$dir" || return 1

  lab=$name
  lab_dir=$dir
  lab_share="$dir/share"
  # Containers that write into the lab directory run as you, so the files
  # they create belong to you instead of root.
  lab_user="$(id -u):$(id -g)"
  export COMPOSE_PROJECT_NAME="$name"
  export WEB_PORT="$port"

  echo "Lab name:      $lab"
  echo "Lab directory: $lab_dir"
  echo "Web port:      $WEB_PORT"
}

# Confirms that the lab directory is the one lab_setup created.
lab_check_directory() {
  local owner

  if [ -z "${lab:-}" ] || [ -z "${lab_dir:-}" ]; then
    lab_fail "this shell has no lab. Run cleanup from the terminal where you sourced the helpers." || return 1
  fi
  case $lab in
    dockerscenes-????????????????) ;;
    *) lab_fail "the lab name changed to '$lab'. Nothing was removed." || return 1 ;;
  esac
  if [ "$(basename "$lab_dir")" != "$lab" ] || [ ! -f "$lab_dir/.lab-owner" ]; then
    lab_fail "the lab directory '$lab_dir' doesn't belong to $lab. Nothing was removed." || return 1
  fi
  owner=$(cat "$lab_dir/.lab-owner") || return 1
  if [ "$owner" != "$lab" ]; then
    lab_fail "the lab directory's owner file changed. Nothing was removed." || return 1
  fi
}

# Prints the value of the docker-lab label on one container or image.
lab_label() {
  local kind=$1
  local id=$2

  docker "$kind" inspect --format '{{index .Config.Labels "docker-lab"}}' "$id"
}

# Runs one removal. If it fails, earlier removals can't be undone, so say so.
lab_remove() {
  if ! docker "$@" >/dev/null; then
    lab_fail "cleanup stopped partway. What it already removed stays removed; fix the error above and run lab_cleanup again." || return 1
  fi
}

lab_cleanup() {
  local kind ids id name names tag found label resource_name parent
  local containers="" networks="" volumes="" images=""

  lab_check_directory || return 1

  # First list and check everything to remove. Nothing is deleted until every
  # check has passed, and any Docker error during the checks stops cleanup.

  # Compose labels everything it creates with the project name, which is the
  # lab's random name. Every such resource must have a name the lab expects.
  for kind in container network volume; do
    ids=$(lab_project_ids "$kind") || return 1
    for id in $ids; do
      resource_name=$(lab_resource_name "$kind" "$id") || return 1
      case "$kind:$resource_name" in
        "container:/$lab-web-1" | "container:/$lab-api-1" | "container:/$lab-db-1") containers="$containers $id" ;;
        "network:${lab}_default") networks="$networks $id" ;;
        "volume:${lab}_dbdata") volumes="$volumes $id" ;;
        *)
          lab_fail "unexpected $kind '$resource_name' in project $lab. Inspect it yourself; nothing was removed." || return 1
          ;;
      esac
    done
  done

  # The article's experiment containers carry the lab's label.
  names=$(docker container ls --all --format '{{.Names}}') || return 1
  for name in exit a b; do
    if printf '%s\n' "$names" | grep -Fxq -- "$lab-$name"; then
      label=$(lab_label container "$lab-$name") || return 1
      if [ "$label" != "$lab" ]; then
        lab_fail "container $lab-$name doesn't carry this lab's label, so nothing was removed. If you created it in this lab, check it with 'docker container inspect $lab-$name', remove it with 'docker container rm --force $lab-$name', and run lab_cleanup again." || return 1
      fi
      containers="$containers $lab-$name"
    fi
  done

  # Only the exact tags the article creates, and only if they carry the label.
  for tag in "$lab-layers:latest" "$lab-web:1" "$lab-web:2" "$lab-web:3" "$lab-web:latest" "$lab-api:latest"; do
    found=$(docker image ls --quiet --filter "reference=$tag") || return 1
    if [ -n "$found" ]; then
      label=$(lab_label image "$tag") || return 1
      if [ "$label" != "$lab" ]; then
        lab_fail "image $tag doesn't carry this lab's label, so nothing was removed. If you created it in this lab, check it with 'docker image inspect $tag', remove it with 'docker image rm $tag', and run lab_cleanup again." || return 1
      fi
      images="$images $tag"
    fi
  done

  for id in $containers; do
    lab_remove container rm --force "$id" || return 1
  done
  for id in $networks; do
    lab_remove network rm "$id" || return 1
  done
  for id in $volumes; do
    lab_remove volume rm "$id" || return 1
  done
  # Removing by tag, without --force, leaves any other tag on the same image alone.
  for tag in $images; do
    lab_remove image rm "$tag" || return 1
  done

  parent=$(dirname "$lab_dir")
  cd "$parent" || return 1
  rm -rf -- "$lab_dir" || return 1

  echo "Removed lab $lab: its containers, network, volume, images and directory."
  echo "The base images (node, nginx, postgres) and Docker's build cache stay."

  unset lab lab_dir lab_share lab_user
  unset COMPOSE_PROJECT_NAME WEB_PORT SERVICE_MESSAGE BROWSER_GREETING BUILD_LABEL
}

lab_setup
