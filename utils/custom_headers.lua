-- Per-catalog custom HTTP headers (e.g. API keys, Cloudflare Access tokens)
-- Headers are only sent to the host of the catalog they belong to.

local socket_url = require("socket.url")

local CustomHeaders = {}

local servers = {}

--- Register the catalog list; kept by reference so edits apply immediately
-- @param server_list table List of server configurations
function CustomHeaders.setServers(server_list)
	servers = server_list or {}
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Parse "Name: value; Other: value" (or newline-separated) into a table
-- A ';' only separates headers when followed by "Token:", so cookie values survive.
-- @param text string|nil User input
-- @return table|nil Headers keyed by name, nil if none
function CustomHeaders.parse(text)
	if not text or text:match("^%s*$") then
		return nil
	end
	text = text:gsub(";%s*([%w!#$%%&'*+.^_`|~-]+%s*:)", "\n%1")
	local headers
	for line in text:gmatch("[^\r\n]+") do
		local name, value = line:match("^%s*([%w!#$%%&'*+.^_`|~-]+)%s*:(.*)$")
		if name then
			headers = headers or {}
			headers[name] = trim(value)
		end
	end
	return headers
end

--- Format headers back into the single-line input form
-- @param headers table|nil Headers keyed by name
-- @return string
function CustomHeaders.format(headers)
	if not headers then
		return ""
	end
	local names = {}
	for name in pairs(headers) do
		table.insert(names, name)
	end
	table.sort(names)
	local parts = {}
	for _, name in ipairs(names) do
		table.insert(parts, name .. ": " .. headers[name])
	end
	return table.concat(parts, "; ")
end

local function authority(u)
	local parsed = u and socket_url.parse(u)
	if not parsed or not parsed.host then
		return nil
	end
	return parsed.host:lower() .. ":" .. (parsed.port or (parsed.scheme == "https" and "443" or "80"))
end

--- Find the custom headers for a request URL
-- Picks the same-host catalog with the longest matching URL prefix.
-- @param request_url string
-- @return table|nil Headers keyed by name
function CustomHeaders.forUrl(request_url)
	local target = authority(request_url)
	if not target then
		return nil
	end
	local best, best_len = nil, -1
	for _, server in ipairs(servers) do
		if server.headers and authority(server.url) == target then
			local base = server.url:gsub("%%s.*$", "")
			local len = request_url:sub(1, #base) == base and #base or 0
			if len > best_len then
				best, best_len = server.headers, len
			end
		end
	end
	return best
end

--- Merge custom headers for request_url into a request headers table
-- @param request_headers table|nil Existing request headers
-- @param request_url string
-- @return table Request headers
function CustomHeaders.apply(request_headers, request_url)
	request_headers = request_headers or {}
	local custom = CustomHeaders.forUrl(request_url)
	if custom then
		for name, value in pairs(custom) do
			request_headers[name] = value
		end
	end
	return request_headers
end

return CustomHeaders
