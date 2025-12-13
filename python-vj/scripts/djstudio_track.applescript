-- DJ.Studio Track Metadata Helper
-- Attempts to get current track from DJ.Studio via AppleScript
-- Outputs a single JSON object describing the current track

on replace_chars(this_text, search_string, replacement_string)
	set AppleScript's text item delimiters to search_string
	set the item_list to every text item of this_text
	set AppleScript's text item delimiters to replacement_string
	set this_text to the item_list as string
	set AppleScript's text item delimiters to ""
	return this_text
end replace_chars

on escape_json(value)
	if value is missing value then return ""
	set quoteChar to ASCII character 34
	set value to replace_chars(value, "\\", "\\\\")
	set value to replace_chars(value, quoteChar, "\\" & quoteChar)
	set value to replace_chars(value, linefeed, "\\n")
	set value to replace_chars(value, return, "\\n")
	return value
end escape_json

on bool_string(flag)
	if flag then
		return "true"
	else
		return "false"
	end if
end bool_string


try
	-- Check if DJ.Studio is running
	tell application "System Events"
		set djstudioRunning to (exists process "DJ.Studio")
	end tell
	
	if djstudioRunning is false then
		error "DJ.Studio is not running" number 2010
	end if
	
	-- DJ.Studio may not support AppleScript directly
	-- This script will attempt to check if it's scriptable
	tell application "System Events"
		tell process "DJ.Studio"
			-- Try to get window information which might contain track info
			set windowCount to count of windows
			if windowCount > 0 then
				set windowTitle to name of window 1
			else
				set windowTitle to ""
			end if
		end tell
	end tell
	
	-- Return JSON with available information
	set quoteChar to ASCII character 34
	set jsonText to "{"
	set jsonText to jsonText & quoteChar & "status" & quoteChar & ":" & quoteChar & "ok" & quoteChar & ","
	set jsonText to jsonText & quoteChar & "running" & quoteChar & ":true,"
	set jsonText to jsonText & quoteChar & "window_title" & quoteChar & ":" & quoteChar & escape_json(windowTitle) & quoteChar & ","
	set jsonText to jsonText & quoteChar & "scriptable" & quoteChar & ":false,"
	set jsonText to jsonText & quoteChar & "note" & quoteChar & ":" & quoteChar & "DJ.Studio may require file monitoring instead of AppleScript" & quoteChar
	set jsonText to jsonText & "}"
	return jsonText
	
on error errMsg number errNum
	error errMsg number errNum
end try
