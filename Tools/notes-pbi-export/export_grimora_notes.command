#!/bin/bash
# Double-click this file in Finder to export raw data from the "Grimora"
# Apple Notes folder. See export_grimora_notes.applescript for details.
#
# First run will trigger macOS permission prompts for Notes/Finder
# automation -- approve them once and you're set for future runs.

cd "$(dirname "$0")"
osascript export_grimora_notes.applescript
