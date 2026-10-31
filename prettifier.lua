--
-- Private
--

local function make_key_path(parent, key)
	if not parent then
		return key
	else
		return string.format("%s.%s", parent, key)
	end
end

local function make_parts(parts, parent, name, something, visited_parents, indent_str, level, style)
	local indent = indent_str:rep(level)
	table.insert(parts, indent)

	local type_of_something = type(something)

	local reference
	if parent and name then
		table.insert(parts, name)

		reference = visited_parents[something]
		if reference then
			table.insert(parts, " -> ")
			type_of_something = "reference"
		else
			table.insert(parts, " = ")
		end
	end

	if reference then
		table.insert(parts, style.ref(reference))
	elseif type_of_something == "table" then
		level = level + 1
		table.insert(parts, style.brace("{"))
		table.insert(parts, "\n")

		visited_parents[something] = make_key_path(parent, name)
		for key, value in pairs(something) do
			make_parts(parts, name, key, value, visited_parents, indent_str, level, style)
		end
		visited_parents[something] = nil

		local metatable = getmetatable(something)
		if metatable then
			make_parts(parts, name, "<metatable>", metatable, visited_parents, indent_str, level, style)
		end

		table.insert(parts, indent)
		table.insert(parts, style.brace("}"))
	elseif type_of_something == "string" then
		table.insert(parts, style.string(string.format("%q", something)))
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
		make_parts(parts, nil, nil, value, {}, indent_str, indent_level, style)
		return parts
	end
end

--
-- Export

return {
	make = make,
}

