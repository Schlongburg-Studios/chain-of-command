-- Chain of Command test runner (Lua 5.4).
--   lua tests/run.lua            run everything
--   lua tests/run.lua -v         also print passing checks
--   lua tests/run.lua structure  run only suites whose name contains "structure"
-- Each suite runs in a fresh sandbox with mocked FiveM, oxmysql, ox_lib and framework.

local script = (arg and arg[0]) or 'tests/run.lua'
local root = script:match('^(.*)[/\\]tests[/\\]run%.lua$') or '.'
package.path = root .. '/tests/?.lua;' .. package.path

local T = require 'lib.t'
local Env = require 'lib.env'

local filter
for _, a in ipairs(arg or {}) do
    if a == '-v' then T.verbose = true else filter = a end
end

local runs = {
    { framework = 'qbx', editable = true,  suites = { 'roster', 'sync', 'structure', 'qbx_multijob' } },
    { framework = 'qb',  editable = true,  suites = { 'roster', 'sync', 'structure' } },
    { framework = 'qbx', editable = false, suites = { 'roster', 'sync', 'qbx_multijob' } },
    { framework = 'qb',  editable = false, suites = { 'roster', 'sync' } },
}

-- cmd_chain prints startup lines; keep the output focused on results.
local realPrint = print
local function quiet(fn)
    print = function() end
    local ok, err = xpcall(fn, debug.traceback)
    print = realPrint
    return ok, err
end

for _, run in ipairs(runs) do
    for _, suiteName in ipairs(run.suites) do
        if not filter or suiteName:find(filter, 1, true) then
            local label = ('%s editor=%s %s'):format(run.framework, run.editable and 'on' or 'off', suiteName)
            T.label_(label)
            local before = T.fails + T.passes
            local base = { root = root, framework = run.framework, editable = run.editable }
            local suite = assert(loadfile(root .. '/tests/suites/' .. suiteName .. '.lua'))()
            local ok, err = quiet(function()
                local E = Env.new(base)
                -- restore print inside checks so failures still show
                local check = T.check
                T.check = function(...) print = realPrint; check(...); print = function() end end
                suite(E, T, Env, base)
                T.check = check
            end)
            if not ok then
                T.fails = T.fails + 1
                local line = ('  ERROR [%s] %s'):format(label, err)
                T.failures[#T.failures + 1] = line
                realPrint(line)
            end
            realPrint(('%-40s %d checks'):format(label, T.fails + T.passes - before))
        end
    end
end

realPrint(('\n%d passed, %d failed'):format(T.passes, T.fails))
if T.fails > 0 then os.exit(1) end
