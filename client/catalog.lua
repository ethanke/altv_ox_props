local Preview = require 'client.preview'

---@type table[]
local categories = require 'data.catalog'

local catalogOpen = false
local indexBuilt = false

---@type { id: string, label: string, count: number }[]
local categoryMeta = {}

---@type { model: string, categoryId: string, categoryLabel: string }[]
local flatModels = {}

local function buildIndex()
    if indexBuilt then return end

    categoryMeta = {}
    flatModels = {}
    local seenModels = {}

    for i = 1, #categories do
        local cat = categories[i]
        local models = cat.models or {}
        local categoryCount = 0

        categoryMeta[#categoryMeta + 1] = {
            id = cat.id,
            label = cat.label,
            count = 0,
        }

        for j = 1, #models do
            local model = models[j]
            if type(model) == 'string' and not seenModels[model] then
                seenModels[model] = true
                categoryCount += 1
                flatModels[#flatModels + 1] = {
                    model = model,
                    categoryId = cat.id,
                    categoryLabel = cat.label,
                }
            end
        end

        categoryMeta[#categoryMeta].count = categoryCount
    end

    indexBuilt = true
end

---Sends catalog payload to NUI and focuses it.
function OpenCatalog()
    if catalogOpen then return end
    if not IsEditing then return end

    buildIndex()

    local sets = GetSets()
    local set = sets[GetTargetSetId()]
    local workingSet = set and set.name or locale('editor.set_global_name')

    catalogOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'catalog:open',
        data = {
            categories = categoryMeta,
            models = flatModels,
            workingSet = workingSet,
            preview = Preview.nuiConfig(),
            locale = {
                title = locale('catalog.title'),
                search = locale('catalog.search'),
                all = locale('catalog.all'),
                place = locale('catalog.place'),
                copy = locale('catalog.copy'),
                forge = locale('catalog.forge'),
                custom = locale('catalog.custom'),
                close = locale('catalog.close'),
                empty = locale('catalog.empty'),
                results = locale('catalog.results'),
            },
        },
    })
end

---Closes the catalog NUI without placing.
function CloseCatalog()
    if not catalogOpen then return end

    catalogOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'catalog:close' })
end

---@return boolean
function IsCatalogOpen()
    return catalogOpen
end

---Enters cursor/gizmo mode if not already active.
local function ensureCursorMode()
    if not IsEditing then return end
    EnterCursorModeIfNeeded()
end

RegisterNUICallback('catalog:close', function(_, cb)
    CloseCatalog()
    cb(1)
end)

RegisterNUICallback('catalog:place', function(data, cb)
    local model = data and data.model
    cb(1)

    if type(model) ~= 'string' or model == '' then return end

    CloseCatalog()

    local ok = StartPlacingProp(model:lower():gsub('%s+', ''), GetTargetSetId())
    if ok then
        ensureCursorMode()
    end
end)

RegisterNUICallback('catalog:copy', function(data, cb)
    local model = data and data.model
    cb(1)

    if type(model) ~= 'string' or model == '' then return end

    lib.setClipboard(model)
    lib.notify({ description = locale('catalog.copied', model), type = 'success' })
end)

RegisterNUICallback('catalog:forge', function(data, cb)
    local model = data and data.model
    cb(1)

    if type(model) ~= 'string' or model == '' then return end

    local resolved = Preview.resolve(model)
    -- FiveM cannot open an external browser reliably from client Lua; copy the
    -- Forge URL so the admin can paste it, and push it to NUI for optional use.
    lib.setClipboard(resolved.forgeUrl)
    lib.notify({ description = locale('catalog.forge_copied'), type = 'inform' })

    SendNUIMessage({
        action = 'catalog:forge',
        data = { url = resolved.forgeUrl, model = model },
    })
end)

RegisterNUICallback('catalog:custom', function(_, cb)
    cb(1)
    CloseCatalog()

    local input = lib.inputDialog(locale('editor.add_prop'), {
        {
            type = 'input',
            label = locale('editor.model_name'),
            description = locale('editor.model_name_desc'),
            placeholder = 'prop_bin_05a',
            required = true,
            minLength = 1,
            maxLength = 64,
        },
    })

    if not input or not input[1] then return end

    local model = input[1]:lower():gsub('%s+', '')
    local ok = StartPlacingProp(model, GetTargetSetId())
    if ok then
        ensureCursorMode()
    end
end)

RegisterNUICallback('catalog:preview', function(data, cb)
    local model = data and data.model
    if type(model) ~= 'string' or model == '' then
        cb({})
        return
    end

    cb(Preview.resolve(model))
end)

exports('openCatalog', function()
    if not IsEditing then return false end
    OpenCatalog()
    return true
end)
