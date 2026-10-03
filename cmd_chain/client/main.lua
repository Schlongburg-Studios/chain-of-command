-- Client cache for UI only. The server re-checks every action.

local state = { members = {}, caps = {}, primary = nil }
local capSets = {}

RegisterNetEvent('cmd_chain:client:sync', function(data)
    state = data or { members = {}, caps = {} }
    capSets = {}
    for deptId, caps in pairs(state.caps or {}) do
        local set = {}
        for _, cap in ipairs(caps) do set[cap] = true end
        capSets[deptId] = set
    end
end)

local function requestSync()
    lib.callback('cmd_chain:sync', false, function() end)
end

if Bridge then
    Bridge.onPlayerLoaded(requestSync)
    Bridge.onJobUpdate(requestSync)
end

CreateThread(function()
    Wait(1000)
    requestSync() -- covers resource restarts while players are already loaded
end)

local function defaultDept()
    if state.primary and state.members[state.primary] then return state.primary end
    local ids = {}
    for id in pairs(state.members) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids[1]
end

---@param deptId string?
---@return table? member
local function GetMyMember(deptId)
    return state.members[deptId or defaultDept() or '']
end

---Cached, for UI only. Without deptId: true if any of your departments grants cap.
---@param cap string
---@param deptId string?
---@return boolean
local function HasPermission(cap, deptId)
    if deptId then return capSets[deptId] ~= nil and capSets[deptId][cap] == true end
    for _, set in pairs(capSets) do
        if set[cap] then return true end
    end
    return false
end

exports('GetMyMember', GetMyMember)
exports('HasPermission', HasPermission)

-- ───────────────────────────── /roster menu ─────────────────────────────

local function notify(ok, msg)
    lib.notify({ title = 'Chain of Command', description = msg, type = ok and 'success' or 'error' })
end

local openRoster, openStructure -- forward declarations (menus reopen each other)

local function act(deptId, action, target, value)
    local ok, err = lib.callback.await('cmd_chain:action', false, action, deptId, target, value)
    notify(ok, ok and 'Done.' or err)
    openRoster(deptId)
end

local function gradeOptions(data, filter)
    local options = {}
    for _, rank in ipairs(data.ranks) do
        if filter(rank.grade) then
            options[#options + 1] = { value = rank.grade, label = ('%s (%d)'):format(rank.name, rank.grade) }
        end
    end
    return options
end

local function openMember(data, member)
    local deptId = data.id
    local below = member.grade < data.myGrade and member.citizenid ~= data.myCitizenId
    local options = {}

    if below and HasPermission('roster.promote', deptId) then
        local up = gradeOptions(data, function(g) return g > member.grade and g < data.myGrade end)
        if #up > 0 then
            options[#options + 1] = {
                title = 'Promote', icon = 'arrow-up',
                onSelect = function()
                    local input = lib.inputDialog('Promote ' .. member.name, {
                        { type = 'select', label = 'New rank', options = up, required = true },
                    })
                    if input then act(deptId, 'promote', member.citizenid, input[1]) end
                end,
            }
        end
        local down = gradeOptions(data, function(g) return g < member.grade end)
        if #down > 0 then
            options[#options + 1] = {
                title = 'Demote', icon = 'arrow-down',
                onSelect = function()
                    local input = lib.inputDialog('Demote ' .. member.name, {
                        { type = 'select', label = 'New rank', options = down, required = true },
                    })
                    if input then act(deptId, 'demote', member.citizenid, input[1]) end
                end,
            }
        end
    end

    if below and HasPermission('roster.set_callsign', deptId) then
        options[#options + 1] = {
            title = 'Set callsign', icon = 'id-badge',
            description = data.callsignFormat and ('Format: %s'):format(data.callsignFormat) or nil,
            onSelect = function()
                local input = lib.inputDialog('Callsign for ' .. member.name, {
                    { type = 'input', label = 'Callsign (empty clears)', default = member.callsign or '' },
                })
                if input then act(deptId, 'callsign', member.citizenid, input[1]) end
            end,
        }
    end

    if below and HasPermission('roster.set_division', deptId) and #data.divisions > 0 then
        local divisionOptions = {}
        for _, division in ipairs(data.divisions) do
            divisionOptions[#divisionOptions + 1] = { value = division, label = division }
        end
        options[#options + 1] = {
            title = 'Set divisions', icon = 'layer-group',
            onSelect = function()
                local input = lib.inputDialog('Divisions for ' .. member.name, {
                    { type = 'multi-select', label = 'Divisions', options = divisionOptions, default = member.divisions },
                })
                if input then act(deptId, 'division', member.citizenid, input[1] or {}) end
            end,
        }
    end

    if below and HasPermission('roster.fire', deptId) then
        options[#options + 1] = {
            title = 'Fire', icon = 'user-xmark',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'Fire ' .. member.name .. '?',
                    content = 'They will be removed from ' .. data.label .. '.',
                    centered = true,
                    cancel = true,
                })
                if confirm == 'confirm' then act(deptId, 'fire', member.citizenid) end
            end,
        }
    end

    if #options == 0 then
        options[1] = { title = 'No actions available', disabled = true }
    end

    lib.registerContext({
        id = 'cmd_chain_member',
        title = ('%s · %s'):format(member.name, member.rank),
        menu = 'cmd_chain_roster',
        options = options,
    })
    lib.showContext('cmd_chain_member')
end

openRoster = function(deptId)
    deptId = deptId or defaultDept()
    if not deptId or not state.members[deptId] then
        notify(false, 'You are not in a department.')
        return
    end

    local data = lib.callback.await('cmd_chain:getRoster', false, deptId)
    if not data then
        notify(false, 'Roster unavailable.')
        return
    end

    local options = {}
    if data.canEditStructure then
        options[#options + 1] = {
            title = 'Rank structure', icon = 'sitemap',
            description = 'Add, rename, pay and permissions for ranks',
            onSelect = function() openStructure(deptId) end,
        }
    end

    if HasPermission('roster.hire', deptId) then
        local hireGrades = gradeOptions(data, function(g) return g < data.myGrade end)
        options[#options + 1] = {
            title = 'Hire', icon = 'user-plus',
            description = 'Hire a player by server id',
            onSelect = function()
                local input = lib.inputDialog('Hire into ' .. data.label, {
                    { type = 'number', label = 'Server id', required = true, min = 1 },
                    { type = 'select', label = 'Rank', options = hireGrades, required = true },
                })
                if input then act(deptId, 'hire', input[1], input[2]) end
            end,
        }
    end

    for _, member in ipairs(data.roster) do
        local status = member.online and (member.onDuty and 'On duty' or 'Off duty') or 'Offline'
        local divisions = #member.divisions > 0 and (' · ' .. table.concat(member.divisions, ', ')) or ''
        options[#options + 1] = {
            title = ('%s%s'):format(member.callsign and ('[' .. member.callsign .. '] ') or '', member.name),
            description = ('%s · %s%s'):format(member.rank, status, divisions),
            onSelect = function() openMember(data, member) end,
        }
    end

    lib.registerContext({
        id = 'cmd_chain_roster',
        title = ('%s (%d)'):format(data.label, #data.roster),
        options = options,
    })
    lib.showContext('cmd_chain_roster')
end

-- ───────────────────────────── rank structure editor (v1.1) ─────────────────────────────


local function structureAct(deptId, action, grade, data)
    local ok, err = lib.callback.await('cmd_chain:structure', false, action, deptId, grade, data)
    notify(ok, ok and 'Rank structure saved.' or err)
    openStructure(deptId)
end

local function capOptions(caps)
    local options = {}
    for _, cap in ipairs(caps) do options[#options + 1] = { value = cap, label = cap } end
    return options
end

---Splits "a, b c" into a list.
local function splitCaps(text)
    local list = {}
    for cap in (text or ''):gmatch('[^,%s]+') do list[#list + 1] = cap end
    return list
end

local function capsDialog(data, title, current)
    local fields = {
        { type = 'multi-select', label = 'Capabilities', options = capOptions(data.myCaps), default = current, searchable = true },
    }
    if data.owner then
        fields[2] = { type = 'input', label = 'Custom capabilities (comma-separated)', placeholder = 'mdt.access, reports.delete' }
    end
    local input = lib.inputDialog(title, fields)
    if not input then return nil end
    local caps = input[1] or {}
    for _, cap in ipairs(splitCaps(input[2])) do caps[#caps + 1] = cap end
    return caps
end

local function openRank(data, rank)
    local deptId = data.id
    local options = {
        {
            title = 'Rename', icon = 'pen',
            onSelect = function()
                local input = lib.inputDialog('Rename ' .. rank.name, {
                    { type = 'input', label = 'Rank name', default = rank.name, required = true, max = 50 },
                })
                if input then structureAct(deptId, 'set', rank.grade, { name = input[1] }) end
            end,
        },
        {
            title = 'Set pay', icon = 'dollar-sign', description = ('Current: $%d'):format(rank.payment or 0),
            onSelect = function()
                local input = lib.inputDialog('Pay for ' .. rank.name, {
                    { type = 'number', label = 'Pay per paycheck', default = rank.payment or 0, min = 0, max = data.maxPayment, required = true },
                })
                if input then structureAct(deptId, 'set', rank.grade, { payment = input[1] }) end
            end,
        },
        {
            title = 'Edit capabilities', icon = 'key',
            description = #rank.caps > 0 and table.concat(rank.caps, ', ') or 'None (inherits ranks below)',
            onSelect = function()
                local caps = capsDialog(data, 'Capabilities for ' .. rank.name, rank.caps)
                if caps then structureAct(deptId, 'set', rank.grade, { caps = caps }) end
            end,
        },
        {
            title = 'Delete rank', icon = 'trash',
            disabled = rank.holders > 0,
            description = rank.holders > 0 and ('%d member(s) hold this rank. Move them first.'):format(rank.holders) or nil,
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = ('Delete %s (grade %d)?'):format(rank.name, rank.grade),
                    content = 'The grade is removed from the framework job as well.',
                    centered = true,
                    cancel = true,
                })
                if confirm == 'confirm' then structureAct(deptId, 'remove', rank.grade) end
            end,
        },
    }

    lib.registerContext({
        id = 'cmd_chain_rank',
        title = ('[%d] %s'):format(rank.grade, rank.name),
        menu = 'cmd_chain_structure',
        options = options,
    })
    lib.showContext('cmd_chain_rank')
end

local function addRankDialog(data)
    local used = {}
    for _, rank in ipairs(data.ranks) do used[rank.grade] = true end
    local suggestion
    for g = 0, data.maxGrade do
        if not used[g] then suggestion = g break end
    end
    if not suggestion then
        notify(false, 'No free grade numbers below your rank.')
        return
    end

    local fields = {
        { type = 'number', label = ('Grade number (0-%d, must be unused)'):format(data.maxGrade), default = suggestion, min = 0, max = data.maxGrade, required = true },
        { type = 'input', label = 'Rank name', required = true, max = 50 },
        { type = 'number', label = 'Pay per paycheck', default = 0, min = 0, max = data.maxPayment, required = true },
        { type = 'multi-select', label = 'Capabilities', options = capOptions(data.myCaps), searchable = true },
    }
    local input = lib.inputDialog('Add rank to ' .. data.label, fields)
    if not input then return end
    if used[input[1]] then
        notify(false, 'That grade number is already a rank. Edit it instead.')
        return openStructure(data.id)
    end
    structureAct(data.id, 'set', input[1], { name = input[2], payment = input[3], caps = input[4] or {} })
end

openStructure = function(deptId)
    local data, err = lib.callback.await('cmd_chain:getStructure', false, deptId)
    if not data then
        notify(false, err or 'You cannot edit ranks.')
        return
    end

    if data.pick then
        local options = {}
        for _, dept in ipairs(data.pick) do
            options[#options + 1] = { title = dept.label, description = dept.id, onSelect = function() openStructure(dept.id) end }
        end
        lib.registerContext({ id = 'cmd_chain_structure_pick', title = 'Rank structure', options = options })
        return lib.showContext('cmd_chain_structure_pick')
    end

    local options = {
        {
            title = 'Add rank', icon = 'plus',
            description = data.owner and 'Owner: any free grade' or 'Below your own rank',
            onSelect = function() addRankDialog(data) end,
        },
    }
    for _, rank in ipairs(data.ranks) do
        local caps = #rank.caps > 0 and table.concat(rank.caps, ', ') or 'no own capabilities'
        options[#options + 1] = {
            title = ('[%d] %s'):format(rank.grade, rank.name),
            description = ('$%d · %s · %d member(s)'):format(rank.payment or 0, caps, rank.holders),
            disabled = not rank.editable,
            onSelect = function() openRank(data, rank) end,
        }
    end
    if not data.savedToJobsFile and data.framework == 'qb' then
        options[#options + 1] = {
            title = 'QBCore note', icon = 'circle-info', disabled = true,
            description = 'Grades are applied by cmd_chain on every start. Keep cmd_chain running.',
        }
    end

    lib.registerContext({
        id = 'cmd_chain_structure',
        title = data.label .. ' · Rank structure',
        options = options,
    })
    lib.showContext('cmd_chain_structure')
end

RegisterCommand('ranks', function(_, args)
    openStructure(args[1])
end, false)

RegisterCommand('roster', function(_, args)
    openRoster(args[1])
end, false)
