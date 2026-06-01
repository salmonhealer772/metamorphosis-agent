#!/usr/bin/env bash
# Nuerpeel Fleet Cheat Sheet
# Run on {{SERVER_NAME}}

case "${1:-}" in
  ps)
    echo "=== ALL CONTAINERS ==="
    docker ps -a --filter "name=nuerpeel" --format "table {{.Names}}\t{{.Status}}\t{{.ID}}"
    echo ""
    echo "=== RESOURCE USAGE ==="
    docker stats --no-stream --filter "name=nuerpeel"
    ;;
  start)
    echo "=== START DOCKER ==="
    sudo dockerd &
    sleep 2
    echo "Docker started. Check with: sudo docker info"
    ;;
  spawn)
    bash ~/spawn-fleet.sh
    ;;
  kill)
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 kill <name-or-number>"
      echo "  e.g. $0 kill 5          → removes nuerpeel-minion-5"
      echo "  e.g. $0 kill all        → runs clean-fleet.sh"
      exit 1
    fi
    if [ "$2" = "all" ]; then
      bash ~/clean-fleet.sh
    else
      NAME="nuerpeel-minion-${2}"
      echo "Killing ${NAME}..."
      docker rm -f "${NAME}" 2>/dev/null && echo "Done." || echo "Not found."
    fi
    ;;
  *)
    echo "Nuerpeel Fleet Commands"
    echo "  bash fleet.sh ps        — see all containers + resource usage"
    echo "  bash fleet.sh start     — start Docker daemon"
    echo "  bash fleet.sh spawn     — create 40 minions"
    echo "  bash fleet.sh kill <N>  — kill minion N (e.g. kill 5)"
    echo "  bash fleet.sh kill all  — save & destroy everything"
    ;;
esac
