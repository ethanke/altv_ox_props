local config = require 'config'

---@class OxPropSet
---@field id integer
---@field name string
---@field enabled boolean

---@class OxProp
---@field id integer
---@field setId integer
---@field model string
---@field coords vector3
---@field rotation vector3

---Live entities for props currently spawned in the world, keyed by prop id.
---@type table<integer, number>
local spawnedProps = {}

---All props known to this client, keyed by prop id.
---@type table<integer, OxProp>
local props = {}

---All prop sets known to this client, keyed by set id.
---@type table<integer, OxPropSet>
local sets = {}

local isStreaming = false

---Returns true when the prop should currently be visible.
---Props in disabled sets stay in memory; they are simply not spawned.
---@param prop OxProp
---@return boolean
local function isPropVisible(prop)
    local set = sets[prop.setId]
    return not set or set.enabled
end

---Spawns a prop entity, returning nil if the model could not be loaded.
---@param prop OxProp
---@return number? entity
local function spawnProp(prop)
    local model = lib.requestModel(prop.model, 5000)
    if not model or model == 0 then return nil end

    local entity = CreateObjectNoOffset(model, prop.coords.x, prop.coords.y, prop.coords.z, false, false, false)
    if not entity or entity == 0 then return nil end
    SetEntityRotation(entity, prop.rotation.x, prop.rotation.y, prop.rotation.z, 2, false)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, true, true)
    SetModelAsNoLongerNeeded(model)

    return entity
end

---@param id integer
local function despawnProp(id)
    local entity = spawnedProps[id]
    if not entity then return end

    if DoesEntityExist(entity) then DeleteEntity(entity) end
    spawnedProps[id] = nil
end

---Returns the point props should be streamed around.
---
---While the editor is open the player's ped stays where it was, but the camera
---can be flown far away. Streaming from the ped would leave newly placed props
---unspawned, so the editor camera takes priority when it exists.
---@return vector3
local function getStreamingOrigin()
    if IsEditing then
        local camCoords = GetEditorCameraCoords()
        if camCoords then return camCoords end
    end

    return GetEntityCoords(cache.ped)
end

---Streams props in and out based on distance to the player.
local function startStreaming()
    if isStreaming then return end
    isStreaming = true

    CreateThread(function()
        while isStreaming do
            local origin = getStreamingOrigin()

            for id, prop in pairs(props) do
                local distance = #(origin - prop.coords)
                local entity = spawnedProps[id]
                local isSpawned = entity ~= nil and DoesEntityExist(entity)
                local isVisible = isPropVisible(prop)

                -- Forget handles that were deleted out-of-band (e.g. by the
                -- editor or the game); otherwise the prop would never respawn
                -- and the dead handle could be recycled by the engine.
                if entity ~= nil and not isSpawned then
                    spawnedProps[id] = nil
                end

                if not isVisible and isSpawned then
                    despawnProp(id)
                elseif isVisible and distance <= config.renderDistance and not isSpawned then
                    spawnedProps[id] = spawnProp(prop)
                    Wait(config.spawnDelay)
                elseif distance > config.renderDistance and isSpawned then
                    despawnProp(id)
                end
            end

            Wait(1000)
        end
    end)
end

RegisterNetEvent('ox_props:syncProps', function(payload)
    for id in pairs(spawnedProps) do
        despawnProp(id)
    end

    props = {}
    sets = {}

    for i = 1, #(payload.sets or {}) do
        local set = payload.sets[i]
        sets[set.id] = set
    end

    for i = 1, #(payload.props or {}) do
        local prop = payload.props[i]
        props[prop.id] = prop
    end

    startStreaming()
    RefreshPropsListMenu()
end)

RegisterNetEvent('ox_props:setCreated', function(set)
    sets[set.id] = set
    RefreshPropsListMenu()
end)

RegisterNetEvent('ox_props:setRenamed', function(id, name)
    local set = sets[id]
    if not set then return end

    set.name = name
    RefreshPropsListMenu()
end)

---Removes a prop id from the spawned table if it maps to the given entity.
---Exposed for the editor, which deletes entities directly and must not leave
---stale handles behind.
---@param entity number
function spawnedPropsCleanup(entity)
    for id, propEntity in pairs(spawnedProps) do
        if propEntity == entity then
            spawnedProps[id] = nil
            return
        end
    end
end

RegisterNetEvent('ox_props:setEnabled', function(id, enabled)
    local set = sets[id]
    if not set then return end

    set.enabled = enabled

    -- Despawn/respawn immediately so the change feels instant; the streaming
    -- loop also enforces this every second as a safety net.
    for propId, prop in pairs(props) do
        if prop.setId == id then
            if enabled then
                if #(getStreamingOrigin() - prop.coords) <= config.renderDistance and not spawnedProps[propId] then
                    spawnedProps[propId] = spawnProp(prop)
                end
            else
                despawnProp(propId)
            end
        end
    end

    RefreshPropsListMenu()
end)

RegisterNetEvent('ox_props:setRemoved', function(id)
    sets[id] = nil

    if GetTargetSetId() == id then
        SetTargetSetId(0)
    end

    RefreshPropsListMenu()
end)

RegisterNetEvent('ox_props:addProp', function(prop)
    props[prop.id] = prop

    if isPropVisible(prop) and #(getStreamingOrigin() - prop.coords) <= config.renderDistance then
        spawnedProps[prop.id] = spawnProp(prop)
    end

    startStreaming()
    RefreshPropsListMenu()
end)

RegisterNetEvent('ox_props:updateProp', function(id, coords, rotation)
    local prop = props[id]
    if not prop then return end

    prop.coords = coords
    prop.rotation = rotation

    local entity = spawnedProps[id]
    if entity and DoesEntityExist(entity) then
        SetEntityCoords(entity, coords.x, coords.y, coords.z, false, false, false, false)
        SetEntityRotation(entity, rotation.x, rotation.y, rotation.z, 2, false)
    end

    RefreshPropsListMenu()
end)

RegisterNetEvent('ox_props:removeProp', function(id)
    props[id] = nil
    despawnProp(id)
    RefreshPropsListMenu()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    for id in pairs(spawnedProps) do
        despawnProp(id)
    end
end)

---@param id integer
---@return number? entity
function GetPropEntity(id)
    local entity = spawnedProps[id]
    if entity and DoesEntityExist(entity) then return entity end
    return nil
end

---@param entity number
---@return integer? id
function GetPropIdFromEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    for id, propEntity in pairs(spawnedProps) do
        if propEntity == entity and DoesEntityExist(propEntity) then return id end
    end
    return nil
end

---@return table<integer, OxProp>
function GetProps()
    return props
end

---@return table<integer, OxPropSet>
function GetSets()
    return sets
end

---@param setId integer
---@return boolean
function IsSetEnabled(setId)
    local set = sets[setId]
    return not set or set.enabled
end

---@return table<integer, number>
function GetSpawnedProps()
    return spawnedProps
end

---@param id integer
function DespawnProp(id)
    despawnProp(id)
end

---@param prop OxProp
---@return number? entity
function SpawnProp(prop)
    return spawnProp(prop)
end

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('ox_props:requestSync')
end)
