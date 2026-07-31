-- ExternalConfig ModuleScript
-- Put this ModuleScript in ReplicatedStorage and set Url/Token as needed.

return {
    -- URL to fetch JSON config from. Replace with your endpoint.
    Url = "https://example.com/chiba-config.json",

    -- Poll interval in seconds (server will re-fetch periodically)
    PollInterval = 60,

    -- Optional token (Bearer). If your API uses an API key, place it here.
    Token = nil,

    -- If your API returns JSON with a field named "maxCount", the client
    -- will use that value. Example response: { "maxCount": 30 }
}
