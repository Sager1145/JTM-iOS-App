#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
/usr/bin/caffeinate -di ./run.sh all
