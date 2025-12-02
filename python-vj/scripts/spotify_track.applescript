-- Spotify Track Metadata Helper
-- Outputs a single JSON object describing the current Spotify track

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
	set isPlaying to false
	tell application "System Events"
		set spotifyRunning to (exists process "Spotify")
	end tell
	if spotifyRunning is false then
		error "Spotify is not running" number 2010
	end if
	
	tell application "Spotify"
		set playerState to player state
		if playerState is stopped then
			error "Spotify is stopped" number 2011
		end if
		set isPlaying to (playerState is playing)
		set trackRef to current track
		if trackRef is missing value then
			error "No current track" number 2012
		end if
		set trackName to name of trackRef
		set artistName to artist of trackRef
		set albumName to album of trackRef
		set trackDuration to duration of trackRef
		set trackPosition to player position
	end tell
	
	if trackDuration is missing value then set trackDuration to 0
	if trackPosition is missing value then set trackPosition to 0
	
	set quoteChar to ASCII character 34
	set jsonText to "{"
	set jsonText to jsonText & quoteChar & "status" & quoteChar & ":" & quoteChar & "ok" & quoteChar & ","
	set jsonText to jsonText & quoteChar & "player_state" & quoteChar & ":" & quoteChar & playerState & quoteChar & ","
	set jsonText to jsonText & quoteChar & "is_playing" & quoteChar & ":" & bool_string(isPlaying) & ","
	set jsonText to jsonText & quoteChar & "artist" & quoteChar & ":" & quoteChar & escape_json(artistName) & quoteChar & ","
	set jsonText to jsonText & quoteChar & "title" & quoteChar & ":" & quoteChar & escape_json(trackName) & quoteChar & ","
	set jsonText to jsonText & quoteChar & "album" & quoteChar & ":" & quoteChar & escape_json(albumName) & quoteChar & ","
	set jsonText to jsonText & quoteChar & "duration_ms" & quoteChar & ":" & (trackDuration as integer) & ","
	set jsonText to jsonText & quoteChar & "progress_ms" & quoteChar & ":" & (round (trackPosition * 1000))
	set jsonText to jsonText & "}"
	return jsonText
on error errMsg number errNum
	error errMsg number errNum
end try
