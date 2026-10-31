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
	truty = { fg = "magenta" },
	falsy = { fg = "magenta" },
	boolean = { fg = "magenta" },
	number = { fg = "magenta" },
	string = { fg = "green" },
	func = { fg = "blue" },
	ref = { fg = "cyan" },
	mt = { fg = "cyan" },
	null = { fg = "cyan" },
	brace = { fg = "yellow" },
}

local g_options = {
	stop_on_failure = false,
	suite_names = {},
	suite_patterns = {},
	test_names = {},
	test_patterns = {},
	case_names = {},
	case_patterns = {},
	indent_str = "    ",
	verbose_mode = false,

	has_filters = function()
		return #suite_names > 0 or #suite_patterns > 0 or #test_names > 0 or #test_patterns > 0 or #case_names > 0 or #case_patterns > 0
	end
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

--
-- Private
--

local function can_display_colors(desc)
	if vim and vim.version then
		return false
	end

	local first, _, third = os.execute(string.format("[ -t %d ]", desc))

	-- LUA 5.1 / LuaJIT
	if type(first) == "number" then
		return first == 0
	else -- LUA 5.2+
		return first == true and third == 0
	end
end

local function write_line_to(desc)
	return function(what)
		if what then
			desc:write(what)
		end

		desc:write("\n")
	end
end

local function built_in_print(what)
	if what then
		print(what)
	else
		print("\n")
	end
end

local print_message = built_in_print
local print_error = write_line_to(io.stderr)

local function nop()
end

local function next_index(index, last_index)
	local next_index = index + 1
	if next_index > last_index then
		return nil
	end

	return next_index
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

local function should_run(name, exact_strs, patterns)
	if #exact_strs > 0 then
		if not name then
			return false
		end

		for _, str in ipairs(exact_strs) do
			if name == str then
				return true
			end
		end

		return false
	elseif #patterns > 0 then
		if not name then
			return false
		end

		for _, pattern in ipairs(patterns) do
			if name:find(pattern) then
				return true
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
	local help_message = [[
Options:
  -S <name>, --suite <name>            Exact suite name to run
  -s <pattern>, --suite-ptn <pattern>  Suite name pattern to run
  -T <name>, --test <name>             Exact test name to run
  -t <pattern>, --test-ptn <pattern>   Test name pattern to run
  -C <name>, --case <name>             Exact case name to run
  -c <pattern>, --case-ptn <pattern>   Case name pattern to run

    All of the above can be specified multiple times.

  -o, --stdout                         Print directly to stdout, rather than using 'print()' function
  -l, --force_color                    Force colored output, regardless of TTY state
  -p, --no_color                       Force not colored output, regardless of TTY state
  -d <string>, --indent <string>       Use <string> as indent for output
  -v, --verbose                        Verbose mode
  -f, --stop-on-failure                Stop when a test fails
  -g, --debug-info                     Print debug info

  -h, --help                           Show this message
]]

	local paths = {}
	local stdout = false
	local colorize = nil
	local no_color = nil
	local force_color = nil
	local debug_mode = false

	local index = 1
	while index <= #args do
		local arg = args[index]

		if arg == "-S" or arg == "--suite" then
			index = next_index(index, #args)
			if not index then
				print_error(string.format("just-in-case: No value was specified for %q", arg))
				os.exit(1)
			end

			table.insert(g_options.suite_names, args[index])

		elseif arg == "-s" or arg == "--suite-ptn" then
			index = next_index(index, #args)
			if not index then
				print_error(string.format("just-in-case: No value was specified for %q", arg))
				os.exit(1)
			end

			table.insert(g_options.suite_patterns, args[index])

		elseif arg == "-T" or arg == "--test" then
			index = next_index(index, #args)
			if not index then
				print_error(string.format("just-in-case: No value was specified for %q", arg))
				os.exit(1)
			end

			table.insert(g_options.test_names, args[index])

		elseif arg == "-t" or arg == "--test-ptn" then
			index = next_index(index, #args)
			if not index then
				print_error(string.format("just-in-case: No value was specified for %q", arg))
				os.exit(1)
			end

			table.insert(g_options.test_patterns, args[index])

		elseif arg == "-C" or arg == "--case" then
			index = next_index(index, #args)
			if not index then
				print_error(string.format("just-in-case: No value was specified for %q", arg))
				os.exit(1)
			end

			table.insert(g_options.case_names, args[index])

		elseif arg == "-c" or arg == "--case-ptn" then
			index = next_index(index, #args)
			if not index then
				print_error(string.format("just-in-case: No value was specified for %q", arg))
				os.exit(1)
			end

			table.insert(g_options.case_patterns, args[index])

		elseif arg == "-f" or arg == "--stop-on-failure" then
			g_options.stop_on_failure = true

		elseif arg == "-o" or arg == "--stdout" then
			print_message = write_line_to(io.stdout)
			stdout = true

		elseif arg == "-l" or arg == "--force-color" then
			force_color = arg

		elseif arg == "-p" or arg == "--no-color" then
			no_color = arg

		elseif arg == "-d" or arg == "--indent" then
			index = next_index(index, #args)
			if not index then
				print_error(string.format("just-in-case: No value was specified for %q", arg))
				os.exit(1)
			end

			g_options.indent_str = args[index]

		elseif arg == "-v" or arg == "--verbose" then
			g_options.verbose_mode = true

		elseif arg == "-g" or arg == "--debug" then
			debug_mode = true

		elseif arg == "-h" or arg == "--help" then
			print_message(help_message)
			os.exit(0)

		else
			print_error(string.format("just-in-case: Unknown option %q", arg))
			os.exit(1)
		end

		index = index + 1
	end

	local no_color_env = os.getenv("NO_COLOR")
	local force_color_env = os.getenv("FORCE_COLOR")
	local is_a_tty = can_display_colors(1)
	if no_color then
		colorize = false
	elseif force_color then
		colorize = true
	elseif no_color_env then
		colorize = false
	elseif force_color_env then
		if force_color_env ~= "" then
			colorize = true
		end
	elseif is_a_tty then
		colorize = true
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
		print_message("suite names: " .. (Stuff.format_enum("%q", g_options.suite_names) or "none"))
		print_message("suite patterns: " .. (Stuff.format_enum("%q", g_options.suite_patterns) or "none"))

		print_message("test names: " .. (Stuff.format_enum("%q", g_options.test_names) or "none"))
		print_message("test patterns: " .. (Stuff.format_enum("%q", g_options.test_patterns) or "none"))

		print_message("case names: " .. (Stuff.format_enum("%q", g_options.case_names) or "none"))
		print_message("case patterns: " .. (Stuff.format_enum("%q", g_options.case_patterns) or "none"))

		print_message("stdout: " .. (stdout and "true" or "false"))

		do
			local parts = { "colorize: ", (colorize and "true" or "false"), "; decided by " }
			if no_color then
				table.insert(parts, string.format("%q option", no_color))
			elseif force_color then
				table.insert(parts, string.format("%q option", force_color))
			elseif no_color_env then
				table.insert(parts, string.format('"NO_COLOR=%s" environment variable', no_color_env))
			elseif force_color_env then
				table.insert(parts, string.format('"FORCE_COLOR=%s" environment variable', force_color_env))
			elseif is_a_tty then
				table.insert(parts, "stdout being a TTY")
			else
				table.insert(parts, "stdout not being a TTY")
			end

			local message = table.concat(parts)
			print_message(message)
		end

		print_message(string.format("indent string: %q", g_options.indent_str))
		print_message("verbose mode: " .. (g_options.verbose_mode  and "true" or "false"))
		print_message("stop on failure: " .. (g_options.stop_on_failure and "true" or "false"))

		print_message()
	end
end

local function suite(name)
	function run(desc)
		g_suite_number = g_suite_number + 1
		local suite_has_no_fails = true

		local has_suite_name = type(name) == "string"
		if not should_run(has_suite_name and name, g_options.suite_names, g_options.suite_patterns) then
			return
		end

		local suite_name = has_suite_name and name or "Suite #" .. g_suite_number
		local setup = desc.setup or nop
		local teardown = desc.teardown or nop

		if g_options.verbose_mode then
			print_message(suite_name)
		end

		local tests = {}
		for number, test_desc in ipairs(desc) do
			if should_run(test_desc.name, g_options.test_names, g_options.test_patterns) then
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
					if should_run(case.name, g_options.case_names, g_options.case_patterns) then
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
				print_message(test_title)
			end

			local test_func = test_desc[1]

			local test_has_no_fails = true
			for _, case in ipairs(cases_to_run) do
				local setup_result = { setup() }
				local arguments = not case.is_empty_case
					and make_test_func_args(setup_result, case.desc.values)
					or {}

				local ok, result = pcall(test_func, unpack(arguments))
				if not ok then
					if not g_options.verbose_mode then
						if suite_has_no_fails then
							print_message(suite_name)
						end

						if test_has_no_fails then
							print_message(test_title)
						end
					end

					local message = make_error_message(case, result, g_options.indent_str, 2, g_output_style)
					print_message(message)
					print_message()
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

local function report()
	print_message()
	if g_total.failed == 0 then
		local all_passed = "All tests passed."
		local total = "Total: " .. g_total.count
		local separator = string.rep("=", math.max(#total, #all_passed))

		print_message(separator)
		print_message(total)
		print_message(all_passed)
	else
		local total = "Total: " .. g_total.count
		local passed = "Passed: " .. g_total.passed
		local failed = "Failed: " .. g_total.failed
		local separator = string.rep("=", math.max(#total, #passed, #failed))

		print_message(separator)
		print_message(total)
		print_message(passed)
		print_message(failed)

		os.exit(1)
	end
end

--
-- Export

return {
	setup = setup,
	suite = suite,
	test = test,
	case = case,
	report = report,
	expect = Predicates.expect,
}

