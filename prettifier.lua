--
-- Private
--

-- TODO:
--   * handle self-referencing tables
--   * handle metatables, if necessary
local function make_parts(parts, name, something, indent_str, level, style)
	local indent = indent_str:rep(level)

	table.insert(parts, indent)
	if name then
		table.insert(parts, name)
		table.insert(parts, " = ")
	end

	local type_of_something = type(something)
	if type_of_something == "table" then
		level = level + 1
		table.insert(parts, style.brace("{"))
		table.insert(parts, "\n")
		for key, value in pairs(something) do
			make_parts(parts, key, value, indent_str, level, style)
		end
		table.insert(parts, indent)
		table.insert(parts, style.brace("}"))
	elseif type_of_something == "string" then
		table.insert(parts, style.string('"' .. something .. '"'))
	elseif type_of_something == "number" then
		table.insert(parts, style.number(tostring(something)))
	elseif type_of_something == "boolean" then
		table.insert(parts, style.boolean(tostring(something)))
	elseif type_of_something == "nil" then
		table.insert(parts, style.null("<nil>"))
	elseif type_of_something == "function" then
		table.insert(parts, style.func(tostring(something)))
	end

	if name then
		table.insert(parts, ",\n")
	end
end

--
-- Public
--

local function make(style, indent_str)
	return function(value, indent_level)
		indent_level = indent_level or 0
		local parts = {}
		make_parts(parts, nil, value, indent_str, indent_level, style)
		return parts
	end
end

--
-- Export

return {
	make = make,
}

