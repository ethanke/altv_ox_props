local validation = {}

---Validates that a value is a finite number, guarding against NaN/inf from clients.
---@param value any
---@return number?
function validation.number(value)
    if type(value) ~= 'number' then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

---@param coords any
---@return vector3?
function validation.coords(coords)
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return nil end

    local x = validation.number(coords.x)
    local y = validation.number(coords.y)
    local z = validation.number(coords.z)

    if not x or not y or not z then return nil end

    -- Reject anything outside the bounds of the GTA V map.
    if math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2000 then return nil end

    return vec3(x, y, z)
end

---@param rotation any
---@return vector3?
function validation.rotation(rotation)
    if type(rotation) ~= 'table' and type(rotation) ~= 'vector3' then return nil end

    local x = validation.number(rotation.x)
    local y = validation.number(rotation.y)
    local z = validation.number(rotation.z)

    if not x or not y or not z then return nil end

    return vec3(x, y, z)
end

---@param model any
---@return string?
function validation.model(model)
    if type(model) ~= 'string' then return nil end

    model = model:lower():gsub('%s+', '')

    if model == '' or #model > 64 then return nil end
    if not model:match('^[%w_]+$') then return nil end

    return model
end

---Validates a set name: trimmed, non-empty, bounded length.
---@param name any
---@return string?
function validation.setName(name)
    if type(name) ~= 'string' then return nil end

    name = name:gsub('^%s+', ''):gsub('%s+$', '')

    if name == '' or #name > 48 then return nil end

    return name
end

return validation