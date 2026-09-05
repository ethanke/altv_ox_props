---Forward declarations: these menus reference each other, so the locals must
---exist before any handler runs (a later `local function` is not in scope for
---earlier closures — calling it would be a nil-call error).
local registerMainMenu, refreshSetSelectMenu, refreshSetManageMenu, refreshSetOptionsMenu, refreshListMenu

---Prompts for a prop model name and starts placing it into the selected set.
local function addProp()
    OpenCatalog()
end

---Builds the list of placed props for the list menu.
---@param filterSetId? integer When set, only props of this set are listed.
---@return table options
local function buildPropList(filterSetId)
    local props = GetProps()
    local sets = GetSets()
    local options = {}

    local ids = {}
    for id in pairs(props) do
        if not filterSetId or props[id].setId == filterSetId then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)

    for i = 1, #ids do
        local prop = props[ids[i]]
        local set = sets[prop.setId]
        local setLabel = set and set.name or '?'
        local setIcon = (set and set.enabled) and 'cube' or 'eye-slash'

        options[#options + 1] = {
            title = locale('editor.prop_entry', prop.id, prop.model),
            description = ('%s | %.2f, %.2f, %.2f'):format(setLabel, prop.coords.x, prop.coords.y, prop.coords.z),
            icon = setIcon,
            onSelect = function()
                local entity = GetPropEntity(prop.id)

                if not entity then
                    lib.notify({ description = locale('editor.select_prop_first'), type = 'error' })
                    return
                end

                StartEditingProp(entity, prop.id)
            end,
        }
    end

    if #options == 0 then
        options[#options + 1] = {
            title = locale('editor.no_props'),
            disabled = true,
        }
    end

    return options
end

---Rebuilds (or re-registers) the list menu from the current prop table.
---Must be called every time the menu is shown, otherwise the NUI would
---display a stale snapshot of props taken when it was last registered.
function refreshListMenu(filterSetId)
    lib.registerContext({
        id = 'ox_props_listMenu',
        title = locale('editor.list_props'),
        menu = 'ox_props_mainMenu',
        options = buildPropList(filterSetId),
    })
end

---Global hook so editor.lua can refresh the list after props change.
function RefreshPropsListMenu()
    refreshListMenu()

    -- The main menu title contains the active set name, so rebuild it too.
    registerMainMenu()
end

---Builds the per-set management options (toggle, rename, view, delete).
---@param set OxPropSet
---@return table options
local function buildSetOptions(set)
    local options = {}

    options[#options + 1] = {
        title = set.enabled and locale('editor.set_disable') or locale('editor.set_enable'),
        description = set.enabled and locale('editor.set_enabled_desc') or locale('editor.set_disabled_desc'),
        icon = set.enabled and 'eye' or 'eye-slash',
        onSelect = function()
            local success = lib.callback.await('ox_props:toggleSet', false, set.id, not set.enabled)

            if success then
                lib.notify({ description = locale('editor.set_toggled', set.name), type = 'success' })
            end

            refreshSetManageMenu()
            lib.showContext('ox_props_setManageMenu')
        end,
    }

    options[#options + 1] = {
        title = locale('editor.set_view_props'),
        icon = 'list',
        onSelect = function()
            refreshListMenu(set.id)
            lib.showContext('ox_props_listMenu')
        end,
    }

    if set.id ~= 0 then -- the Global set is protected
        options[#options + 1] = {
            title = locale('editor.set_rename'),
            icon = 'pen',
            onSelect = function()
                local input = lib.inputDialog(locale('editor.set_rename'), {
                    {
                        type = 'input',
                        label = locale('editor.set_name'),
                        default = set.name,
                        required = true,
                        minLength = 1,
                        maxLength = 48,
                    },
                })

                if input and input[1] then
                    lib.callback.await('ox_props:renameSet', false, set.id, input[1])
                end

                refreshSetManageMenu()
                lib.showContext('ox_props_setManageMenu')
            end,
        }

        options[#options + 1] = {
            title = locale('editor.set_delete'),
            description = locale('editor.set_delete_desc'),
            icon = 'trash',
            onSelect = function()
                local success = lib.callback.await('ox_props:deleteSet', false, set.id)

                if success then
                    lib.notify({ description = locale('editor.set_deleted', set.name), type = 'success' })
                else
                    lib.notify({ description = locale('editor.set_delete_failed'), type = 'error' })
                end

                refreshSetManageMenu()
                lib.showContext('ox_props_setManageMenu')
            end,
        }
    end

    return options
end

---Builds the management menu for one set.
---@param setId integer
function refreshSetOptionsMenu(setId)
    local set = GetSets()[setId]
    if not set then
        refreshSetManageMenu()
        lib.showContext('ox_props_setManageMenu')
        return
    end

    lib.registerContext({
        id = 'ox_props_setOptionsMenu',
        title = set.name,
        menu = 'ox_props_setManageMenu',
        options = buildSetOptions(set),
    })

    lib.showContext('ox_props_setOptionsMenu')
end

---Builds the set-management menu. Set selection remains a direct action in
---the previous menu, while CRUD operations are grouped behind this menu.
function refreshSetManageMenu()
    local sets = GetSets()
    local ids = {}
    local options = {}

    for id in pairs(sets) do
        ids[#ids + 1] = id
    end
    table.sort(ids)

    for i = 1, #ids do
        local set = sets[ids[i]]

        options[#options + 1] = {
            title = set.name,
            description = set.enabled and locale('editor.set_enabled_desc') or locale('editor.set_disabled_desc'),
            icon = set.enabled and 'layer-group' or 'eye-slash',
            arrow = true,
            onSelect = function()
                refreshSetOptionsMenu(set.id)
            end,
        }
    end

    lib.registerContext({
        id = 'ox_props_setManageMenu',
        title = locale('editor.set_manage'),
        menu = 'ox_props_setSelectMenu',
        options = options,
    })
end

---Returns the display name of the set new props are placed into.
---@return string
local function getTargetSetName()
    local sets = GetSets()
    local set = sets[GetTargetSetId()]
    return set and set.name or locale('editor.set_global_name')
end

---Builds the set-select menu shown when the editor opens. Selecting a set
---makes it the target for new props; each entry also exposes CRUD options.
function refreshSetSelectMenu()
    local sets = GetSets()
    local ids = {}

    for id in pairs(sets) do
        ids[#ids + 1] = id
    end
    table.sort(ids)

    local targetId = GetTargetSetId()
    local options = {}

    for i = 1, #ids do
        local set = sets[ids[i]]
        local isTarget = set.id == targetId

        options[#options + 1] = {
            title = set.name,
            description = (set.enabled and locale('editor.set_enabled_desc') or locale('editor.set_disabled_desc'))
                .. (isTarget and (' | ' .. locale('editor.set_selected_desc')) or ''),
            icon = isTarget and 'circle-check' or (set.enabled and 'layer-group' or 'eye-slash'),
            metadata = { locale('editor.set_id_label', set.id) },
            onSelect = function()
                SetTargetSetId(set.id)

                registerMainMenu()
                lib.showContext('ox_props_mainMenu')
            end,
        }
    end

    options[#options + 1] = {
        title = locale('editor.set_create'),
        icon = 'plus',
        onSelect = function()
            local input = lib.inputDialog(locale('editor.set_create'), {
                {
                    type = 'input',
                    label = locale('editor.set_name_label'),
                    description = locale('editor.set_name_desc'),
                    required = true,
                    minLength = 1,
                    maxLength = 48,
                },
            })

            if input and input[1] then
                local id = lib.callback.await('ox_props:createSet', false, input[1])

                if id then
                    lib.notify({ description = locale('editor.set_created', input[1]), type = 'success' })
                    SetTargetSetId(id)
                    registerMainMenu()
                    lib.showContext('ox_props_mainMenu')
                    return
                end
            end

            refreshSetSelectMenu()
            lib.showContext('ox_props_setSelectMenu')
        end,
    }

    options[#options + 1] = {
        title = locale('editor.set_manage'),
        icon = 'sliders',
        arrow = true,
        onSelect = function()
            refreshSetManageMenu()
            lib.showContext('ox_props_setManageMenu')
        end,
    }

    lib.registerContext({
        id = 'ox_props_setSelectMenu',
        title = locale('editor.set_select_title'),
        options = options,
    })
end

---Registers the main props menu. The title shows the set new props are
---placed into, e.g. "Props - World" or "Props - TestSet".
function registerMainMenu()
    lib.registerContext({
        id = 'ox_props_mainMenu',
        title = ('%s - %s: %s'):format(locale('editor.title'), locale('editor.working_set'), getTargetSetName()),
        options = {
            {
                title = locale('editor.add_prop'),
                icon = 'plus',
                onSelect = addProp,
            },
            {
                title = locale('editor.list_props'),
                icon = 'list',
                onSelect = function()
                    refreshListMenu(GetTargetSetId())
                    lib.showContext('ox_props_listMenu')
                end,
            },
            {
                title = locale('editor.change_working_set'),
                icon = 'arrow-right-arrow-left',
                arrow = true,
                onSelect = function()
                    refreshSetSelectMenu()
                    lib.showContext('ox_props_setSelectMenu')
                end,
            },
            {
                title = locale('editor.set_manage'),
                icon = 'layer-group',
                arrow = true,
                onSelect = function()
                    refreshSetManageMenu()
                    lib.showContext('ox_props_setManageMenu')
                end,
            },
            {
                title = locale('editor.snap_to_ground'),
                icon = 'arrow-down',
                onSelect = function()
                    local entity = GetPreviewObject()
                    if not entity then
                        lib.notify({ description = locale('editor.nothing_selected'), type = 'error' })
                        return
                    end
                    PlaceObjectOnGroundProperly(entity)
                end,
            },
            {
                title = locale('editor.reset_rotation'),
                icon = 'rotate-left',
                onSelect = function()
                    local entity = GetPreviewObject()
                    if not entity then
                        lib.notify({ description = locale('editor.nothing_selected'), type = 'error' })
                        return
                    end
                    SetEntityRotation(entity, 0.0, 0.0, 0.0, 2, false)
                end,
            },
            {
                title = locale('editor.duplicate'),
                icon = 'clone',
                onSelect = function()
                    local entity = GetPreviewObject()
                    if not entity then
                        lib.notify({ description = locale('editor.nothing_selected'), type = 'error' })
                        return
                    end

                    local model = GetEntityArchetypeName(entity)
                    StartPlacingProp(model, GetTargetSetId())
                end,
            },
            {
                title = locale('editor.copy_coords'),
                icon = 'clipboard',
                onSelect = function()
                    local entity = GetPreviewObject()
                    if not entity then
                        lib.notify({ description = locale('editor.nothing_selected'), type = 'error' })
                        return
                    end

                    local coords = GetEntityCoords(entity)
                    local rotation = GetEntityRotation(entity, 2)
                    local formatted = ('vec4(%.4f, %.4f, %.4f, %.4f)'):format(coords.x, coords.y, coords.z, rotation.z)

                    lib.setClipboard(formatted)
                    lib.notify({ description = locale('editor.coords_copied'), type = 'success' })
                end,
            },
            {
                title = locale('editor.goto_prop'),
                icon = 'location-dot',
                onSelect = function()
                    local entity = GetPreviewObject()
                    if not entity then
                        lib.notify({ description = locale('editor.nothing_selected'), type = 'error' })
                        return
                    end

                    FocusCameraOnCoords(GetEntityCoords(entity))
                end,
            },
            {
                title = locale('editor.exit_editor'),
                icon = 'xmark',
                onSelect = function()
                    if IsEditing then ToggleEditing() end
                end,
            },
        },
    })
end

RegisterNetEvent('ox_props:openEditor', function()
    -- Start every new editor session in the set-selection mode. Once a set is
    -- chosen, the target is kept while props are added, duplicated or
    -- cancelled; pressing E then opens the classic props menu.
    if not IsEditing then
        SetTargetSetId(0)
    end

    registerMainMenu()
    refreshSetSelectMenu()

    if not IsEditing then
        ToggleEditing()
    end

    Wait(500)

    -- The set-select menu comes first: a set must be chosen (default World)
    -- before placing props, and its CRUD lives here too.
    lib.showContext('ox_props_setSelectMenu')
end)
