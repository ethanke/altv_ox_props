local config = require 'config'

IsEditing = false

local camera
local previewObject
local cursorMode = false
local lastHighlighted
local lastMatrix
local selectedPropId
local targetSetId = 0

---World position the current prop was grabbed from, used to enforce
---config.gizmoMaxDistance so a prop cannot be dragged arbitrarily far.
local grabOrigin

local IsDisabledControlPressed = IsDisabledControlPressed
local IsDisabledControlJustReleased = IsDisabledControlJustReleased
local SetCamCoord = SetCamCoord
local SetCamRot = SetCamRot
local GetCamCoord = GetCamCoord
local GetCamRot = GetCamRot

---Creates a freecam the editor can fly around with.
local function freeCam()
    local cameraPosition = GetGameplayCamCoord()
    local cameraRotation = GetGameplayCamRot(2)
    local cameraFov = GetGameplayCamFov()

    camera = CreateCameraWithParams('DEFAULT_SCRIPTED_CAMERA', cameraPosition.x, cameraPosition.y, cameraPosition.z, cameraRotation.x, cameraRotation.y, cameraRotation.z, cameraFov, true, 2)

    CreateThread(function()
        local multiplier = 0.1

        while IsEditing do
            cameraPosition = GetCamCoord(camera)
            cameraRotation = GetCamRot(camera, 2)

            local forwardX = -math.sin(math.rad(cameraRotation.z))
            local forwardY = math.cos(math.rad(cameraRotation.z))
            local rightX = math.cos(math.rad(cameraRotation.z))
            local rightY = math.sin(math.rad(cameraRotation.z))
            local upwardZ = math.sin(math.rad(cameraRotation.x))

            if IsDisabledControlPressed(0, 241) then
                multiplier += 0.01
            end

            if IsDisabledControlPressed(0, 242) then
                multiplier -= 0.01
            end

            if multiplier < 0.01 then multiplier = 0.001 end
            if multiplier > 1.0 then multiplier = 1.0 end

            if IsDisabledControlPressed(0, 32) then
                cameraPosition += vector3(forwardX * multiplier, forwardY * multiplier, upwardZ * multiplier)
            end

            if IsDisabledControlPressed(0, 33) then
                cameraPosition -= vector3(forwardX * multiplier, forwardY * multiplier, upwardZ * multiplier)
            end

            if IsDisabledControlPressed(0, 34) then
                cameraPosition -= vector3(rightX * multiplier, rightY * multiplier, 0)
            end

            if IsDisabledControlPressed(0, 35) then
                cameraPosition += vector3(rightX * multiplier, rightY * multiplier, 0)
            end

            if IsDisabledControlPressed(0, 36) then
                cameraPosition -= vector3(0, 0, multiplier)
            end

            if IsDisabledControlPressed(0, 203) then
                cameraPosition += vector3(0, 0, multiplier)
            end

            cameraRotation -= vector3(GetDisabledControlNormal(0, 272) * 5, 0, GetDisabledControlNormal(0, 270) * 5)

            SetCamCoord(camera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
            SetCamRot(camera, math.min(math.max(cameraRotation.x, -89), 89), cameraRotation.y, cameraRotation.z, 2)

            Wait(0)
        end

        DestroyCam(camera, false)
        camera = nil
    end)

    SetPlayerControl(cache.playerId, not IsEditing, 0)
    RenderScriptCams(IsEditing, true, 1000, true, true)
end

local function showText()
    if cursorMode then
        lib.showTextUI(locale('textui.cursor'))
    else
        lib.showTextUI(locale('textui.freecam'))
    end
end

---Builds a 4x4 matrix buffer from an entity, used by the gizmo native.
---@param entity number
---@return table view
local function makeEntityMatrix(entity)
    local f, r, u, a = GetEntityMatrix(entity)
    -- 64 bytes: a full 4x4 float matrix. Writing offset 60 into a 60-byte
    -- buffer only worked because ArrayBuffer can silently reallocate.
    local view = DataView.ArrayBuffer(64)

    view:SetFloat32(0, r[1]):SetFloat32(4, r[2]):SetFloat32(8, r[3]):SetFloat32(12, 0)
        :SetFloat32(16, f[1]):SetFloat32(20, f[2]):SetFloat32(24, f[3]):SetFloat32(28, 0)
        :SetFloat32(32, u[1]):SetFloat32(36, u[2]):SetFloat32(40, u[3]):SetFloat32(44, 0)
        :SetFloat32(48, a[1]):SetFloat32(52, a[2]):SetFloat32(56, a[3]):SetFloat32(60, 1)

    return view
end

---Applies a matrix buffer produced by the gizmo back onto an entity.
---@param entity number
---@param view table
local function applyEntityMatrix(entity, view)
    SetEntityMatrix(entity,
        view:GetFloat32(16), view:GetFloat32(20), view:GetFloat32(24),
        view:GetFloat32(0), view:GetFloat32(4), view:GetFloat32(8),
        view:GetFloat32(32), view:GetFloat32(36), view:GetFloat32(40),
        view:GetFloat32(48), view:GetFloat32(52), view:GetFloat32(56)
    )
end

---@param entity number
---@return integer? propId
local function getPropIdFromEntity(entity)
    return GetPropIdFromEntity(entity)
end

---Clamps the preview object back inside config.gizmoMaxDistance of its grab
---origin if it drifted beyond it during dragging.
local function clampToGrabDistance()
    if not grabOrigin then return end

    local coords = GetEntityCoords(previewObject)
    local offset = coords - grabOrigin
    local distance = #offset

    if distance > config.gizmoMaxDistance then
        local clamped = grabOrigin + (offset / distance) * config.gizmoMaxDistance
        SetEntityCoords(previewObject, clamped.x, clamped.y, clamped.z, false, false, false, false)
        lib.notify({ description = locale('editor.gizmo_distance_clamped'), type = 'error' })
    end
end

---Commits the current transform of the preview object to the server.
local function confirmPlacement()
    if not DoesEntityExist(previewObject) then return end

    clampToGrabDistance()

    local coords = GetEntityCoords(previewObject)
    local rotation = GetEntityRotation(previewObject, 2)
    local propId = selectedPropId

    if propId then
        -- Moving an existing prop: update it in place. The entity is owned by the
        -- streaming system, so it must not be deleted here; the server broadcast
        -- will move it for every client.
        local success = lib.callback.await('ox_props:updateProp', false, propId, coords, rotation)

        if success then
            lib.notify({ description = locale('editor.prop_updated'), type = 'success' })
        end
    else
        -- Placing a brand new prop: the preview object is temporary, so remove it
        -- and let the server broadcast spawn the real one.
        local model = GetEntityArchetypeName(previewObject)
        local id = lib.callback.await('ox_props:addProp', false, model, coords, rotation, targetSetId)

        SetEntityDrawOutline(previewObject, false)
        DeleteEntity(previewObject)

        if id then
            lib.notify({ description = locale('editor.prop_added'), type = 'success' })
        end
    end

    previewObject = nil
    selectedPropId = nil
    lastMatrix = nil
    grabOrigin = nil
end

---Discards the preview object, restoring an existing prop to its original transform.
local function cancelPlacement()
    if DoesEntityExist(previewObject) then
        if selectedPropId then
            applyEntityMatrix(previewObject, lastMatrix)
        else
            DeleteEntity(previewObject)
        end
    end

    previewObject = nil
    selectedPropId = nil
    lastMatrix = nil
    grabOrigin = nil
end

---Spawns a preview object for a model name, ready to be positioned.
---@param model string
---@param setId? integer Set the new prop will belong to (defaults to Global).
---@return boolean success
function StartPlacingProp(model, setId)
    if not IsEditing then return false end

    local modelHash = joaat(model)

    if not IsModelInCdimage(modelHash) then
        lib.notify({ description = locale('editor.invalid_model', model), type = 'error' })
        return false
    end

    -- previewObject may still be a streaming-system-owned entity from a
    -- previous selection. Deleting it here would leave a stale handle in
    -- spawnedProps and permanently hide that prop, so restore it instead.
    if DoesEntityExist(previewObject) then
        cancelPlacement()
    end

    lib.requestModel(modelHash, 5000)

    local camCoords = GetCamCoord(camera)
    local camRotation = GetCamRot(camera, 2)
    local forwardCoords = camCoords + vector3(
        -math.sin(math.rad(camRotation.z)),
        math.cos(math.rad(camRotation.z)),
        math.sin(math.rad(camRotation.x)) * 1.2
    ) * 2

    previewObject = CreateObjectNoOffset(modelHash, forwardCoords.x, forwardCoords.y, forwardCoords.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)
    FreezeEntityPosition(previewObject, true)
    SetEntityCollision(previewObject, false, false)
    SetEntityDrawOutline(previewObject, true)

    selectedPropId = nil
    targetSetId = setId or 0
    lastMatrix = makeEntityMatrix(previewObject)
    grabOrigin = GetEntityCoords(previewObject)

    return true
end

---Begins editing an already-placed prop.
---@param entity number
---@param propId integer
function StartEditingProp(entity, propId)
    if not IsEditing then return end

    if DoesEntityExist(previewObject) then
        cancelPlacement()
    end

    previewObject = entity
    selectedPropId = propId
    lastMatrix = makeEntityMatrix(entity)
    grabOrigin = GetEntityCoords(entity)

    SetEntityDrawOutline(entity, true)
end

---@return number? entity
function GetPreviewObject()
    return previewObject
end

---Returns the id of the set new props will be placed into.
---@return integer
function GetTargetSetId()
    return targetSetId
end

---Sets the target set for new props (used by the set-select menu).
---@param setId integer
function SetTargetSetId(setId)
    targetSetId = setId
end

---@return integer? propId
function GetSelectedPropId()
    return selectedPropId
end

---Moves the editor camera to a set of coordinates.
---@param coords vector3
function FocusCameraOnCoords(coords)
    if not camera then return end
    SetCamCoord(camera, coords.x, coords.y, coords.z + 2.0)
end

---Returns the current editor camera position, or nil when no camera exists.
---@return vector3?
function GetEditorCameraCoords()
    if not camera then return nil end
    return GetCamCoord(camera)
end

function ToggleEditing()
    IsEditing = not IsEditing

    freeCam()
    showText()

    while IsEditing do
        Wait(0)

        if cursorMode then
            local entity = SelectEntityAtCursor((1 << 5), true)

            if entity ~= lastHighlighted then
                if getPropIdFromEntity(entity) then
                    SetEntityDrawOutline(entity, true)
                end
                SetEntityDrawOutline(lastHighlighted, false)
                lastHighlighted = entity
            end

            -- Left click selects the highlighted prop for editing.
            if IsDisabledControlJustReleased(0, 24) and previewObject ~= entity and entity ~= 0 then
                local propId = getPropIdFromEntity(entity)

                if propId then
                    if lastMatrix and DoesEntityExist(previewObject) then
                        applyEntityMatrix(previewObject, lastMatrix)
                    end

                    StartEditingProp(entity, propId)
                end
            end
        end

        -- BACKSPACE: exit the editor.
        if IsDisabledControlJustReleased(0, 202) then
            cancelPlacement()
            SetEntityDrawOutline(lastHighlighted, false)
            ToggleEditing()
            break
        end

        -- E: open the props menu.
        if IsDisabledControlJustReleased(0, 38) then
            lib.showContext('ox_props_mainMenu')
        end

        -- LALT: toggle cursor mode.
        if IsDisabledControlJustReleased(0, 19) then
            cursorMode = not cursorMode
            showText()

            if cursorMode then
                -- EnterCursorMode/LeaveCursorMode are the game's native cursor
                -- controls; they enable the mouse and gizmo interaction.
                EnterCursorMode()
            else
                SetEntityDrawOutline(lastHighlighted, false)
                LeaveCursorMode()
            end
        end

        -- DEL: delete the selected prop.
        if IsDisabledControlJustReleased(0, 214) and DoesEntityExist(previewObject) and selectedPropId then
            local alert = lib.alertDialog({
                header = locale('editor.confirm_delete'),
                content = locale('editor.confirm_delete_content'),
                centered = true,
                cancel = true,
            })

            if alert == 'confirm' then
                local propId = selectedPropId
                local entity = previewObject
                local success = lib.callback.await('ox_props:removeProp', false, propId)

                if success then
                    lib.notify({ description = locale('editor.prop_removed'), type = 'success' })

                    -- The broadcast despawns the entity on every client, but on
                    -- this client it may have arrived before the callback
                    -- returned (or spawnedProps may still hold the handle);
                    -- delete the local entity directly so it never lingers.
                    if DoesEntityExist(entity) then DeleteEntity(entity) end
                    spawnedPropsCleanup(entity)
                end

                SetEntityDrawOutline(entity, false)
                previewObject = nil
                selectedPropId = nil
                lastMatrix = nil
                grabOrigin = nil
            end
        end

        -- G: snap to ground.
        if IsDisabledControlJustReleased(0, 47) and DoesEntityExist(previewObject) then
            PlaceObjectOnGroundProperly(previewObject)
        end

        -- ENTER: confirm placement.
        if IsDisabledControlJustReleased(0, 191) and DoesEntityExist(previewObject) then
            confirmPlacement()
        end

        -- Drive the gizmo for the current preview object.
        if DoesEntityExist(previewObject) then
            local matrixBuffer = makeEntityMatrix(previewObject)
            local changed = Citizen.InvokeNative(0xEB2EDCA2, matrixBuffer:Buffer(), 'Editor1', Citizen.ReturnResultAnyway())

            if changed then
                applyEntityMatrix(previewObject, matrixBuffer)
            end
        end
    end

    if CloseCatalog then CloseCatalog() end
    lib.hideTextUI()

    if cursorMode then LeaveCursorMode() end
    cursorMode = false
end

RegisterKeyMapping('+gizmoTranslation', locale('keyMappings.gizmo_translation'), 'keyboard', 'T')
RegisterKeyMapping('+gizmoRotation', locale('keyMappings.gizmo_rotation'), 'keyboard', 'R')
RegisterKeyMapping('+gizmoSelect', locale('keyMappings.gizmo_select'), 'MOUSE_BUTTON', 'MOUSE_LEFT')
RegisterKeyMapping('+gizmoLocal', locale('keyMappings.gizmo_local'), 'keyboard', 'L')

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    if IsEditing then
        IsEditing = false
        RenderScriptCams(false, true, 1000, true, true)
        SetPlayerControl(cache.playerId, true, 0)
        lib.hideTextUI()
        if CloseCatalog then CloseCatalog() end
        if cursorMode then LeaveCursorMode() end
    end
end)
