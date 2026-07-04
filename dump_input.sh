#!/bin/bash
f=/root/.local/share/ares/settings.bml
sed -n '77,145p' "$f" 2>/dev/null
