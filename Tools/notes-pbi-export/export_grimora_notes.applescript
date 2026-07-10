-- export_grimora_notes.applescript
--
-- Exports every note in the Apple Notes "Grimora" folder to a raw staging
-- area so it can be turned into PBI prompt files for an AI agent.
--
-- This script ONLY dumps raw data (title, HTML body, attachments in their
-- native format). It does not decide which notes are "done" and does not
-- touch tasks/inbox/ directly -- that filtering/formatting is handled by
-- process_export.py, which can run anywhere that can see this repo.
--
-- Output (relative to this repo):
--   tasks/_notes_export/manifest.tsv          <- id, title, modified date
--   tasks/_notes_export/raw/<id>/title.txt
--   tasks/_notes_export/raw/<id>/body.html
--   tasks/_notes_export/raw/<id>/attachments/<original filename>
--
-- Run it by double-clicking export_grimora_notes.command in the same folder.
-- The first run will prompt for permission to control Notes and Finder --
-- that's normal macOS automation permission, just approve it once.

set repoRoot to (POSIX path of (path to home folder)) & "Developer/projects/scrydaddy/"
set exportRoot to repoRoot & "tasks/_notes_export/"
set rawFolder to exportRoot & "raw/"

do shell script "mkdir -p " & quoted form of rawFolder

set manifestLines to {}

tell application "Notes"
	-- Find the Grimora folder by name, wherever it sits in the folder tree
	set targetFolder to missing value
	repeat with f in every folder
		if name of f is "Grimora" then
			set targetFolder to f
			exit repeat
		end if
	end repeat
	if targetFolder is missing value then
		display dialog "Couldn't find a Notes folder named \"Grimora\". Check the folder name and try again." buttons {"OK"} default button 1 with icon 2
		error "Grimora folder not found"
	end if

	set theNotes to notes of targetFolder
	set noteCount to count of theNotes

	repeat with i from 1 to noteCount
		set aNote to item i of theNotes
		set noteId to id of aNote as string
		set noteName to name of aNote
		set noteBody to body of aNote
		set noteModified to (modification date of aNote) as string

		set safeId to my sanitizeForPath(noteId)
		set noteFolder to rawFolder & safeId & "/"
		set attFolder to noteFolder & "attachments/"
		do shell script "mkdir -p " & quoted form of attFolder

		my writeTextFile(noteFolder & "title.txt", noteName)
		my writeTextFile(noteFolder & "body.html", noteBody)

		try
			set theAttachments to attachments of aNote
			set attIndex to 0
			repeat with anAttachment in theAttachments
				set attIndex to attIndex + 1
				set attName to ""
				try
					set attName to name of anAttachment
				end try
				if attName is missing value or attName is "" then
					set attName to "attachment-" & attIndex
				end if
				set attName to my sanitizeFileName(attName)
				try
					save anAttachment in (POSIX file (attFolder & attName))
				end try
			end repeat
		end try

		set end of manifestLines to (safeId & tab & noteName & tab & noteModified)
	end repeat
end tell

set manifestText to ""
repeat with l in manifestLines
	set manifestText to manifestText & l & linefeed
end repeat
my writeTextFile(exportRoot & "manifest.tsv", manifestText)

display dialog "Exported " & (count of manifestLines) & " notes from Grimora." & linefeed & linefeed & "Raw data is in tasks/_notes_export/. Now ask Claude to process it into PBI files." buttons {"OK"} default button 1

on sanitizeForPath(theText)
	set allowedChars to "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
	set outStr to ""
	repeat with c in characters of theText
		if allowedChars contains c then
			set outStr to outStr & c
		else
			set outStr to outStr & "_"
		end if
	end repeat
	return outStr
end sanitizeForPath

on sanitizeFileName(theText)
	set badChars to "/:\\"
	set outStr to ""
	repeat with c in characters of theText
		if badChars contains c then
			set outStr to outStr & "_"
		else
			set outStr to outStr & c
		end if
	end repeat
	return outStr
end sanitizeFileName

on writeTextFile(posixPath, theText)
	set theFile to open for access POSIX file posixPath with write permission
	set eof theFile to 0
	write theText to theFile as «class utf8»
	close access theFile
end writeTextFile
