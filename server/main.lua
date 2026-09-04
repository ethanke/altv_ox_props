local config = require 'config'
local storage = require 'server.storage'
local validation = require 'server.validation'

---@class OxPropSet
---@field id integer
---@field name string
---@field enabled boolean Synced to all clients; disabled sets are hidden but kept in memory.

---@class OxProp
---@field id integer
---@field setId integer Set this prop belongs to.
---@field model string
---@field coords vector3
---@field rotation vector3
---@field owner? number Source of the player that created the prop.

local props = {}
local nextId = 1
local propCount = 0

local sets = {}
local nextSetId = 1

local persist = config.persist

---Creates the default set that receives props placed without a set.
---It is always enabled, cannot be renamed or deleted, and is runtime-only
---(never written to the database).
local GLOBAL_SET_ID = 0
sets[GLOBAL_SET_ID] = { id = GLOBAL_SET_ID, name = 'Global', enabled = true }
nextSetId = 1

local isReady = false

---Waits for the initial database load before handling stateful requests.
local function waitForReady()
    while not isReady do
        Wait(0)
    end
end

---Loads persisted sets and props from the database when config.persist is
---enabled. The Global set (id 0) is runtime-only and never stored.
CreateThread(function()
    local dbSets, dbProps

    if persist then
        dbSets, dbProps = storage.load()

        for i = 1, #dbSets do
            local row = dbSets[i]
            sets[row.id] = { id = row.id, name = row.name, enabled = row.enabled == 1 }

            if row.id >= nextSetId then
                nextSetId = row.id + 1
            end
        end

        for i = 1, #dbProps do
            local row = dbProps[i]

            -- Skip orphaned rows defensively (e.g. FK constraints disabled).
            if sets[row.set_id] then
                props[row.id] = {
                    id = row.id,
                    setId = row.set_id,
                    model = row.model,
                    coords = vec3(row.x, row.y, row.z),
                    rotation = vec3(row.rx, row.ry, row.rz),
                }

                if row.id >= nextId then
                    nextId = row.id + 1
                end
                propCount += 1
            end
        end
    end

    isReady = true

    if persist then
        lib.print.info(('loaded %d set(s) and %d prop(s) from the database.'):format(#dbSets, #dbProps))
    else
        lib.print.info('database persistence is disabled; props are runtime-only.')
    end
end)

---Checks whether a player is a member of a principal (e.g. 'group.admin').
---
---`IsPlayerAceAllowed` only resolves aces, so principal membership has to be
---tested by checking whether any of the player's identifiers inherits from it.
---@param source number
---@param principal string
---@return boolean
local function hasPrincipal(source, principal)
    local identifiers = GetPlayerIdentifiers(source)

    for i = 1, #identifiers do
        if IsPrincipalAceAllowed(identifiers[i], principal) then return true end
    end

    return false
end

---Checks whether a player may manage props.
---
---`config.permission` is treated as an ace first (e.g. 'admin'). A principal
---(e.g. 'group.admin') is also accepted for convenience, since passing one to
---`IsPlayerAceAllowed` would silently deny every request.
---@param source number
---@return boolean
local function hasPermission(source)
    if source == 0 then return true end -- console

    if IsPlayerAceAllowed(source, config.permission) then return true end

    return hasPrincipal(source, config.permission)
end

---@param source number
---@param model string
---@param coords vector3
---@param rotation vector3
---@param setId integer
---@return integer? id
local function createProp(source, model, coords, rotation, setId)
    if propCount >= config.maxProps then
        TriggerClientEvent('ox_lib:notify', source, {
            title = locale('editor.title'),
            description = locale('editor.max_props_reached', config.maxProps),
            type = 'error',
        })
        return nil
    end

    local id = nextId
    nextId += 1
    propCount += 1

    props[id] = {
        id = id,
        setId = setId,
        model = model,
        coords = coords,
        rotation = rotation,
        owner = source,
    }

    return id
end

---Sends the full prop and set state to a single player.
---@param source number
local function syncProps(source)
    local propPayload = {}

    for _, prop in pairs(props) do
        propPayload[#propPayload + 1] = prop
    end

    local setPayload = {}

    for _, set in pairs(sets) do
        setPayload[#setPayload + 1] = set
    end

    TriggerClientEvent('ox_props:syncProps', source, {
        sets = setPayload,
        props = propPayload,
    })
end

lib.callback.register('ox_props:addProp', function(source, model, coords, rotation, setId)
    waitForReady()

    if not hasPermission(source) then return nil end

    model = validation.model(model)
    coords = validation.coords(coords)
    rotation = validation.rotation(rotation)

    if not model or not coords or not rotation then return nil end

    -- Unknown or missing set falls back to the always-enabled Global set.
    setId = (type(setId) == 'number' and sets[setId]) and setId or GLOBAL_SET_ID

    local id = createProp(source, model, coords, rotation, setId)
    if not id then return nil end

    if persist then
        -- Persist after the in-memory create so the id used for the broadcast
        -- is stable; a failed insert only costs persistence, not the session.
        local dbId = storage.insertProp(props[id])

        if dbId and dbId ~= id then
            -- The database assigned a different id (e.g. after a restart with
            -- deleted rows). Re-key the prop so future updates/removals match.
            props[id] = nil
            props[dbId] = { id = dbId, setId = setId, model = model, coords = coords, rotation = rotation, owner = source }
            id = dbId
        end

        if dbId and dbId >= nextId then
            nextId = dbId + 1
        end
    end

    TriggerClientEvent('ox_props:addProp', -1, props[id])

    return id
end)

lib.callback.register('ox_props:updateProp', function(source, id, coords, rotation)
    waitForReady()

    if not hasPermission(source) then return false end

    local prop = props[id]
    if not prop then return false end

    coords = validation.coords(coords)
    rotation = validation.rotation(rotation)

    if not coords or not rotation then return false end

    prop.coords = coords
    prop.rotation = rotation

    if persist then storage.updateProp(id, coords, rotation) end

    TriggerClientEvent('ox_props:updateProp', -1, id, coords, rotation)

    return true
end)

lib.callback.register('ox_props:removeProp', function(source, id)
    waitForReady()

    if not hasPermission(source) then return false end

    if not props[id] then return false end

    props[id] = nil
    propCount -= 1

    if persist then storage.deleteProp(id) end

    TriggerClientEvent('ox_props:removeProp', -1, id)

    return true
end)

---Creates a new, enabled prop set.
lib.callback.register('ox_props:createSet', function(source, name)
    waitForReady()

    if not hasPermission(source) then return nil end

    name = validation.setName(name)
    if not name then return nil end

    local id = persist and storage.createSet(name) or nextSetId

    sets[id] = { id = id, name = name, enabled = true }

    if id >= nextSetId then
        nextSetId = id + 1
    end

    TriggerClientEvent('ox_props:setCreated', -1, sets[id])

    return id
end)

---Renames a set. The Global set cannot be renamed.
lib.callback.register('ox_props:renameSet', function(source, id, name)
    waitForReady()

    if not hasPermission(source) then return false end

    local set = sets[id]
    if not set or id == GLOBAL_SET_ID then return false end

    name = validation.setName(name)
    if not name then return false end

    set.name = name

    if persist then storage.renameSet(id, name) end

    TriggerClientEvent('ox_props:setRenamed', -1, id, name)

    return true
end)

---Enables or disables a set. Disabled sets are hidden on every client but
---their props stay in memory, so re-enabling is instant.
lib.callback.register('ox_props:toggleSet', function(source, id, enabled)
    waitForReady()

    if not hasPermission(source) then return false end

    local set = sets[id]
    if not set or type(enabled) ~= 'boolean' then return false end

    set.enabled = enabled

    if persist then storage.setEnabled(id, enabled) end

    TriggerClientEvent('ox_props:setEnabled', -1, id, enabled)

    return true
end)

---Deletes a set. Only empty sets can be deleted; the Global set is protected.
lib.callback.register('ox_props:deleteSet', function(source, id)
    waitForReady()

    if not hasPermission(source) then return false end

    if id == GLOBAL_SET_ID or not sets[id] then return false end

    for _, prop in pairs(props) do
        if prop.setId == id then return false end
    end

    sets[id] = nil

    -- Props of this set are removed with it (FK ON DELETE CASCADE); drop them
    -- from memory and count as well.
    if persist then storage.deleteSet(id) end

    for propId, prop in pairs(props) do
        if prop.setId == id then
            props[propId] = nil
            propCount -= 1
        end
    end

    TriggerClientEvent('ox_props:setRemoved', -1, id)

    return true
end)


RegisterNetEvent('ox_props:requestSync', function()
    waitForReady()

    if not hasPermission(source) then return end
    syncProps(source)
end)

lib.addCommand(config.command, {
    help = locale('command_help'),
    restricted = config.permission,
}, function(source)
    TriggerClientEvent('ox_props:openEditor', source)
end)
