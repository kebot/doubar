-- Example AppleScript to send events to Doubar

-- Configuration
property doubarPort : 3030
property doubarHost : "127.0.0.1"

-- Function to send event
on sendEvent(eventType, eventData)
	set theURL to "http://" & doubarHost & ":" & doubarPort & "/events"
	set jsonData to "{\"type\":\"" & eventType & "\",\"data\":" & eventData & "}"

	try
		do shell script "curl -s -X POST " & quoted form of theURL & " -H 'Content-Type: application/json' -d " & quoted form of jsonData
		return true
	on error errMsg
		display dialog "Failed to send event: " & errMsg buttons {"OK"} default button 1
		return false
	end try
end sendEvent

-- Example: Send refresh event
on sendRefresh()
	sendEvent("refresh", "{}")
end sendRefresh

-- Example: Send focus event with data
on sendFocus(workspaceId)
	set jsonData to "{\"workspace\":\"" & workspaceId & "\"}"
	sendEvent("focus", jsonData)
end sendFocus

-- Example: Send custom event
on sendCustomEvent(eventType, customData)
	sendEvent(eventType, customData)
end sendCustomEvent

-- Main execution examples
-- Uncomment the one you want to use:

sendRefresh()
-- sendFocus("1")
-- sendCustomEvent("custom", "{\"key\":\"value\"}")
