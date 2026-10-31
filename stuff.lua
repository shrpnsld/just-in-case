--
-- Private
--

-- Quick and dirty temporary solution
local function tables_equal(first, second)
	local keys = {}
	for key, _ in pairs(first) do
		table.insert(keys, key)
	end

	for key, _ in pairs(second) do
		table.insert(keys, key)
	end

	for _, key in ipairs(keys) do
		local first_value = first[key]
		if not first_value then
			return false
		end

		local second_value = second[key]
		if not second_value then
			return false
		end

		if type(first_value) == "table" then
			if type(second_value) ~= "table" then
				return false
			end

			if not tables_equal(first_value, second_value) then
				return false
			end
		elseif first_value ~= second_value then
			return false
		end
	end

	return true
end

--
-- Public
--

-- Quick and dirty temporary solution
local function is_array(tbl)
	return tbl[1] ~= nil
end

local function insert_array(into, array)
	for _, item in ipairs(array) do
		table.insert(into, item)
	end
end

local function concat_arrays(first, second)
	local result = {}
	insert_array(result, first)
	insert_array(result, second)

	return result
end

local function values_equal(first, second)
	if type(first) == "table" then
		if type(second) ~= "table" then
			return false
		end

		return tables_equal(first, second)
	else
		return first == second
	end
end

local function integer_length(number)
	local length = 0
	while number > 1 do
		number = number / 10
		length = length + 1
	end

	return length
end

--
-- Export

return {
	is_array = is_array,
	insert_array = insert_array,
	concat_arrays = concat_arrays,
	values_equal = values_equal,
	integer_length = integer_length,
}
