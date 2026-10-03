-- Tiny assertion helper shared by all suites.
local T = { passes = 0, fails = 0, failures = {}, label = '', verbose = false }

function T.label_(label) T.label = label end

function T.check(name, cond, extra)
    if cond then
        T.passes = T.passes + 1
        if T.verbose then print(('  PASS [%s] %s'):format(T.label, name)) end
    else
        T.fails = T.fails + 1
        local line = ('  FAIL [%s] %s%s'):format(T.label, name, extra ~= nil and (' :: ' .. tostring(extra)) or '')
        T.failures[#T.failures + 1] = line
        print(line)
    end
end

return T
