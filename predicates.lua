local Stuff = require("just-in-case.stuff")

--
-- Global
--

local g_style = {}

--
-- Private
--

local prettify = nil
--
-- Public
--

local function setup(config)
	prettify = config.prettify
	g_style = config.style
end

local function expect(subject)
	local predicates = {
		is_equal_to = function(value)
			if not Stuff.values_equal(subject, value) then
				local parts = { "expected " }
				local is_message_multiline = false

				do
					if type(value) == "table" then
						table.insert(parts, "\n")
						Stuff.insert_array(parts, prettify(value, 1))
						table.insert(parts, "\n")
						table.insert(parts, "got")
						is_message_multiline = true
					else
						Stuff.insert_array(parts, prettify(value))
						table.insert(parts, ", got ")
					end
				end

				do
					if type(subject) == "table" then
						table.insert(parts, "\n")
						Stuff.insert_array(parts, prettify(subject, 1))
						is_message_multiline = true
					else
						Stuff.insert_array(parts, prettify(subject))
					end
				end

				local message = table.concat(parts)

				error {
					message = message,
					is_message_multiline = is_message_multiline,
				}
			end
		end,

		has_type = function(type_name)
			local subject_type = type(subject)
			if subject_type ~= type_name then
				local message = string.format("expected type %q, got %q", type_name, subject_type)

				error {
					message = message,
					is_message_miltiline = false,
				}
			end
		end,

		is_truthy = function()
			if not subject then
				local parts = { "expected ", g_style.boolean("truthy"), " value, got " }
				Stuff.insert_array(parts, prettify(subject))

				local message = table.concat(parts)

				error {
					message = message,
					is_message_multiline = false,
				}
			end
		end,

		is_falsy = function()
			if subject then
				local parts = { "expected ", g_style.boolean("falsy"), " value, got" }
				local is_message_multiline = false

				if type(subject) == "table" then
					table.insert(parts, "\n")
					Stuff.insert_array(parts, prettify(subject, 1))
					is_message_multiline = true
				else
					table.insert(parts, " ")
					Stuff.insert_array(parts, prettify(subject))
				end

				local message = table.concat(parts)

				error {
					message = message,
					is_message_multiline = is_message_multiline,
				}
			end
		end,
	}

	local predicates_mt = {
		__index = function(_, key)
			local message = string.format([[unknown predicate "%s()"]], key)

			error {
				message = message,
				is_message_multiline = false,
			}
		end,
	}

	setmetatable(predicates, predicates_mt)

	return predicates
end

--
-- Export

return {
	setup = setup,
	expect = expect,
}

