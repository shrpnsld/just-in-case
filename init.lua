local Stuff = require("just-in-case.stuff")
local Style = require("just-in-case.style")
local Predicates = require("just-in-case.predicates")
local Prettifier = require("just-in-case.prettifier")

--
-- Global
--

local g_default_output_style_spec = {
	error = { fg = "red" },
	passed = { fg = "green" },
}

local g_predicate_default_output_style_spec = {
	boolean = { fg = "magenta" },
	string = { fg = "green" },
	number = { fg = "magenta" },
	null = { fg = "cyan" },
	func = { fg = "yellow" },
	brace = { fg = "yellow" },
	truty = { fg = "magenta" },
	falsy = { fg = "magenta" },
}

local g_options = {
	stop_on_failure = false,
	suite_name = nil,
	suite_patterns = {},
	test_name = nil,
	test_patterns = {},
	case_name = nil,
	case_patterns = {},
	indent_str = "    ",
	verbose_mode = false,
}

local g_output_style = nil
local g_suite_number = 0
local g_total = {
	count = 0,
	passed = 0,
	failed = 0,

	add = function(self, passed)
		self.count = self.count + 1
		if passed then
			self.passed = self.passed + 1
		else
			self.failed = self.failed + 1
		end
	end
}

local help_message = [[
Options:
    -S <name>, --suite <name>              exact suite name to run.
    -s <pattern>, --suite-ptn <pattern>    suite name pattern to run.
    -T <name>, --test <name>               exact test name to run.
    -t <pattern>, --test-ptn <pattern>     test name pattern to run.
    -C <name>, --case <name>               exact case name to run.
    -c <pattern>, --case-ptn <pattern>     case name pattern to run.

    -p, --plain                            plain output (no colors).
    -d <string>, --indent <string>         use <string> as indent for ouput.
    -v, --verbose                          verbose mode.

    -f, --stop-on-failure                  stop running tests when a test fails.

    -g, --debug-info                       print debug info.
    -h, --help                             show this message.
]]

--
-- Private
--

local function nop()
end

local function extract_test_cases(test_desc)
	local cases = {}
	for index = 2, #test_desc do
		table.insert(cases, test_desc[index])
	end

	return cases
end

local function make_test_func_args(setup_values, case_values)
	if type(setup_values) == "table" and Stuff.is_array(setup_values) then
		if type(case_values) == "table" and Stuff.is_array(case_values) then
			return Stuff.concat_arrays(setup_values, case_values)
		else
			table.insert(setup_values, case_values)
			return setup_values
		end
	elseif setup_values ~= nil then
		if type(case_values) == "table" and Stuff.is_array(case_values) then
			table.insert(case_values, 1, setup_values)
			return case_values
		else
			return { setup_values, case_values }
		end
	else
		if type(case_values) == "table" and Stuff.is_array(case_values) then
			return case_values
		else
			return { case_values }
		end
	end
end

local function should_run(name, exact_str, patterns)
	if exact_str then
		return name == exact_str
	elseif #patterns > 0 then
		if name then
			for _, pattern in ipairs(patterns) do
				if name:find(pattern) then
					return true
				end
			end
		end

		return false
	else
		return true
	end
end

local function make_case_title(case)
	if case.desc.name then
		return string.format("%q", case.desc.name)
	else
		return "#" .. case.number
	end
end

local function make_error_message(case, result, indent_str, level, style)
	local parts = { indent_str:rep(level), style.error("Failed:"), " " }

	if not case.is_empty_case then
		table.insert(parts, "case ")
		table.insert(parts, make_case_title(case))
		table.insert(parts, " ")
	end

	if type(result) == "table" then
		if result.is_message_multiline then
			table.insert(parts, "\n")
			local indent = indent_str:rep(level + 1)
			local description = indent .. result.message:gsub("\n", "\n" .. indent)
			table.insert(parts, description)
		else
			if not case.is_empty_case then
				table.insert(parts, "\n")
				table.insert(parts, indent_str:rep(level + 1))
			end

			table.insert(parts, result.message)
		end
	else
		table.insert(parts, result)
	end

	return table.concat(parts)
end

--
-- Public
--

local function setup(args)
	local paths = {}
	local colorize = true
	local debug_mode = false

	local index = 1
	while index <= #args do
		local arg = args[index]

		if arg == "-S" or arg == "--suite" then
			index = index + 1
			g_options.suite_name = args[index]

		elseif arg == "-s" or arg == "--suite-ptn" then
			index = index + 1
			table.insert(g_options.suite_patterns, args[index])

		elseif arg == "-T" or arg == "--test" then
			index = index + 1
			g_options.test_name = args[index]

		elseif arg == "-t" or arg == "--test-ptn" then
			index = index + 1
			table.insert(g_options.test_patterns, args[index])

		elseif arg == "-C" or arg == "--case" then
			index = index + 1
			g_options.case_name = args[index]

		elseif arg == "-c" or arg == "--case-ptn" then
			index = index + 1
			table.insert(g_options.case_patterns, args[index])

		elseif arg == "-f" or arg == "--stop-on-failure" then
			g_options.stop_on_failure = true

		elseif arg == "-p" or arg == "--plain" then
			colorize = false

		elseif arg == "-d" or arg == "--indent" then
			index = index + 1
			g_options.indent_str = args[index]

		elseif arg == "-g" or arg == "--debug" then
			debug_mode = true

		elseif arg == "-v" or arg == "--verbose" then
			g_options.verbose_mode = true

		elseif arg == "-h" or arg == "--help" then
			print(help_message)
			os.exit(0)

		else
			io.stderr:write("just-in-case: Unknown option '" .. arg .. "'\n")
			os.exit(1)
		end

		index = index + 1
	end

	do
		local output_style_spec = colorize and g_default_output_style_spec or {}
		g_output_style = Style.make(output_style_spec)
	end

	do
		local style_spec = colorize and g_predicate_default_output_style_spec or {}
		local style = Style.make(style_spec)
		local prettify = Prettifier.make(style, g_options.indent_str)
		Predicates.setup {
			prettify = prettify,
			style = style,
		}
	end

	if debug_mode then
		print(string.format("suite name: %q", g_options.suite_name))
		print(string.format("suite pattern: %q", g_options.suite_pattern))

		print(string.format("test name: %q", g_options.test_name))
		print(string.format("test pattern: %q", g_options.test_pattern))

		print(string.format("case name: %q", g_options.case_name))
		print(string.format("case pattern: %q", g_options.case_pattern))

		print("plain output: " .. (colorize and "true" or "false"))
		print(string.format("indent string: %q", g_options.indent_str))
		print("verbose mode: " .. (g_options.verbose_mode  and "true" or "false"))
		print("stop on failure: " .. (g_options.stop_on_failure and "true" or "false"))
	end
end

local function suite(name)
	function run(desc)
		g_suite_number = g_suite_number + 1
		local suite_has_no_fails = true

		local has_suite_name = type(name) == "string"
		if not should_run(has_suite_name and name, g_options.suite_name, g_options.suite_patterns) then
			return
		end

		local suite_name = has_suite_name and name or "Suite #" .. g_suite_number
		local setup = desc.setup or nop
		local teardown = desc.teardown or nop

		if g_options.verbose_mode then
			print(suite_name)
		end

		local tests = {}
		for number, test_desc in ipairs(desc) do
			if should_run(test_desc.name, g_options.test_name, g_options.test_patterns) then
				table.insert(tests, {
					number = number,
					desc = test_desc,
				})
			end
		end

		for _, test in ipairs(tests) do
			local test_number = test.number
			local test_desc = test.desc

			-- NOTE: tests are allowed to have or not to have casses.
			--       handling both variants separately
			--       produces even worse code than this solution.
			--       that's why tests with no cases have a special
			--       list of cases: `{ "none" }`.
			local all_cases = extract_test_cases(test_desc)
			local cases_to_run = {}
			if #all_cases > 0 then
				for case_number, case in ipairs(all_cases) do
					if should_run(case.name, g_options.case_name, g_options.case_patterns) then
						table.insert(cases_to_run, {
							number = case_number,
							desc = case,
						})
					end
				end
			elseif g_options.case_name or #g_options.case_patterns > 0 then
				cases_to_run = {}
			else
				cases_to_run = { { is_empty_case = true } }
			end

			local test_name = test_desc.name or "Test #" .. test_number
			local test_title = string.format("%s%s", g_options.indent_str, test_name)
			if g_options.verbose_mode and #cases_to_run > 0 then
				print(test_title)
			end

			local test_func = test_desc[1]

			local test_has_no_fails = true
			for _, case in ipairs(cases_to_run) do
				local setup_result = { setup() }
				local arguments = not case.is_empty_case
				and make_test_func_args(setup_result, case.desc.values)
				or {}

				local ok, result = pcall(test_func, table.unpack(arguments))
				if not ok then
					if not g_options.verbose_mode then
						if suite_has_no_fails then
							print(suite_name)
						end

						if test_has_no_fails then
							print(test_title)
						end
					end

					local message = make_error_message(case, result, g_options.indent_str, 2, g_output_style)
					print(message)
					print()
				end

				teardown()

				if not ok then
					suite_has_no_fails = false
					test_has_no_fails = false
					if g_options.stop_on_failure then
						break
					end
				end
			end

			g_total:add(test_has_no_fails)

			if not test_has_no_fails and g_options.stop_on_failure then
				break
			end
		end
	end

	if type(name) == "string" then
		return run
	else
		run(name)
	end
end

local function test(param)
	if type(param) == "string" then
		return function(desc)
			desc.name = param
			return desc
		end
	else
		return param
	end
end

local function case(param)
	if type(param) == "string" then
		return function(values)
			return {
				name = param,
				values = values,
			}
		end
	else
		return { values = param }
	end
end

local function stats()
	print()
	if g_total.failed == 0 then
		print("=================")
		print("All tests passed.")
	else
		local separator
		do
			local max_stat = math.max(g_total.passed, g_total.failed)
			local max_stat_length = Stuff.integer_length(max_stat)
			separator = string.rep("=", 8 + max_stat_length)
		end

		print(separator)
		print("Passed: " .. g_total.passed)
		print("Failed: " .. g_total.failed)
	end
end

--
-- Export

return {
	setup = setup,
	suite = suite,
	test = test,
	case = case,
	stats = stats,
	expect = Predicates.expect,
}

