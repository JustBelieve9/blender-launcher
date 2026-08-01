#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift Scripts/generate_icon.swift
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
rm -rf AppIcon.iconset

echo "Built: Resources/AppIcon.icns"
