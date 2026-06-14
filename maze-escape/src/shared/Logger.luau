-- Logger.luau
-- Unified logging for server and client

local RunService = game:GetService("RunService")

local Logger = {}

local SIDE = RunService:IsServer() and "Server" or "Client"

local LEVELS = {
	DEBUG = 1,
	INFO  = 2,
	WARN  = 3,
	ERROR = 4,
}

-- Set to DEBUG for verbose output during development
local MIN_LEVEL = LEVELS.DEBUG

local function formatMessage(tag: string, level: string, message: string, ...): string
	local extra = ""
	local args = { ... }
	if #args > 0 then
		local parts = {}
		for _, arg in ipairs(args) do
			table.insert(parts, tostring(arg))
		end
		extra = " | " .. table.concat(parts, ", ")
	end
	return string.format("[%s][%s][%s] %s%s", SIDE, level, tag, message, extra)
end

local function log(levelName: string, levelNum: number, tag: string, message: string, ...)
	if levelNum < MIN_LEVEL then
		return
	end
	local text = formatMessage(tag, levelName, message, ...)
	if levelNum >= LEVELS.ERROR then
		warn(text)
	else
		print(text)
	end
end

function Logger.debug(tag: string, message: string, ...)
	log("DEBUG", LEVELS.DEBUG, tag, message, ...)
end

function Logger.info(tag: string, message: string, ...)
	log("INFO", LEVELS.INFO, tag, message, ...)
end

function Logger.warn(tag: string, message: string, ...)
	log("WARN", LEVELS.WARN, tag, message, ...)
end

function Logger.error(tag: string, message: string, ...)
	log("ERROR", LEVELS.ERROR, tag, message, ...)
end

function Logger.requireModule(tag: string, moduleScript: ModuleScript)
	Logger.debug(tag, "Loading module", moduleScript:GetFullName())
	local ok, result = pcall(require, moduleScript)
	if not ok then
		Logger.error(tag, "Failed to load module", moduleScript.Name, result)
		error(result, 2)
	end
	Logger.debug(tag, "Module loaded", moduleScript.Name)
	return result
end

return Logger
