--
-- Private
--

local g_codes_for_attributes = {
	fg = {
		["black"] = "30",
		["red"] = "31",
		["green"] = "32",
		["yellow"] = "33",
		["blue"] = "34",
		["magenta"] = "35",
		["cyan"] = "36",
		["white"] = "37",
		["gray"] = "90",
		["bright-red"] = "91",
		["bright-green"] = "92",
		["bright-yellow"] = "93",
		["bright-blue"] = "94",
		["bright-magenta"] = "95",
		["bright-cyan"] = "96",
		["bright-white"] = "97",
	},

	bg = {
		["black"] = "40",
		["red"] = "41",
		["green"] = "42",
		["yellow"] = "43",
		["blue"] = "44",
		["magenta"] = "45",
		["cyan"] = "46",
		["white"] = "47",
		["gray"] = "100",
		["bright-red"] = "101",
		["bright-green"] = "102",
		["bright-yellow"] = "103",
		["bright-blue"] = "104",
		["bright-magenta"] = "105",
		["bright-cyan"] = "106",
		["bright-white"] = "107",
	},

	["bold"] = "1",
	["faint"] = "2",
	["italic"] = "3",
	["underline"] = "4",
	["strike"] = "9",
}

local function make_style(code)
	local style = {}

	local style_mt = {
		__call = function(_, str)
			return code .. str .. "\27[0m"
		end,

		__concat = function(_, str)
			return code .. str
		end,
	}

	setmetatable(style, style_mt)

	return style
end

--
-- Public
--

local function make(specs)
	local sheet = {}
	for name, attributes in pairs(specs) do
		local codes = {}
		for attribute, value in pairs(attributes) do
			local result = g_codes_for_attributes[attribute]
			local code = type(result) == "table" and result[value] or result
			table.insert(codes, code)
		end

		local sequence = "\27[" .. table.concat(codes, ";") .. "m"
		sheet[name] = make_style(sequence)
	end

	local sheet_mt = {
		__index = function()
			return function(str)
				return str
			end
		end
	}

	setmetatable(sheet, sheet_mt)

	return sheet
end

--
-- Export

return {
	make = make,
}
