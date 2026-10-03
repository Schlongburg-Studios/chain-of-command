Audit = {}

local function encode(value)
    if value == nil then return nil end
    if type(value) == 'table' then return next(value) == nil and '[]' or json.encode(value) end
    return tostring(value)
end

---Writes one audit row. actorCid nil = server console or an external change.
---@param dept string
---@param actorCid string?
---@param targetCid string? nil for rank-structure changes
---@param action string
---@param old any
---@param new any
function Audit.log(dept, actorCid, targetCid, action, old, new)
    -- Build the column list from non-nil values: a nil hole in an oxmysql parameter
    -- array can shift the remaining parameters. Omitted columns default to NULL.
    local columns, params = { 'dept', 'action' }, { dept, action }
    local optional = {
        { 'actor_citizenid', actorCid },
        { 'target_citizenid', targetCid },
        { 'old_value', encode(old) },
        { 'new_value', encode(new) },
    }
    for _, pair in ipairs(optional) do
        if pair[2] ~= nil then
            columns[#columns + 1] = pair[1]
            params[#params + 1] = pair[2]
        end
    end
    MySQL.insert(('INSERT INTO cmd_chain_audit (%s) VALUES (%s)'):format(
        table.concat(columns, ', '), ('?'):rep(#columns, ', ')), params)
    if Config.Debug then
        print(('[cmd_chain] audit %s %s %s -> %s: %s => %s'):format(
            dept, actorCid or 'system', targetCid, action, encode(old) or 'nil', encode(new) or 'nil'))
    end
end

---Newest first.
---@param dept string
---@param limit integer?
---@param targetCid string?
function Audit.get(dept, limit, targetCid)
    limit = math.min(math.max(tonumber(limit) or 50, 1), 500)
    if targetCid then
        return MySQL.query.await(
            'SELECT * FROM cmd_chain_audit WHERE dept = ? AND target_citizenid = ? ORDER BY id DESC LIMIT ?',
            { dept, targetCid, limit }) or {}
    end
    return MySQL.query.await(
        'SELECT * FROM cmd_chain_audit WHERE dept = ? ORDER BY id DESC LIMIT ?',
        { dept, limit }) or {}
end
