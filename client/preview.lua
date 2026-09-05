local config = require 'config'

local Preview = {}

---Formats a printf-style URL template with a model name.
---@param template? string
---@param model string
---@return string?
local function formatUrl(template, model)
    if not template or template == '' then return nil end
    return template:format(model)
end

---Resolves preview asset URLs for a model based on config.preview.
---@param model string
---@return { thumbnailUrl: string?, meshUrl: string?, forgeUrl: string }
function Preview.resolve(model)
    local preview = config.preview or {}
    local forgeUrl = formatUrl(preview.forgeObjectUrl or 'https://forge.plebmasters.de/objects/%s', model)
        or ('https://forge.plebmasters.de/objects/' .. model)

    if not preview.enabled or preview.provider == 'none' then
        return {
            thumbnailUrl = nil,
            meshUrl = nil,
            forgeUrl = forgeUrl,
        }
    end

    if preview.provider == 'url' or preview.provider == 'forge' then
        return {
            thumbnailUrl = formatUrl(preview.thumbnailUrl, model),
            meshUrl = formatUrl(preview.meshUrl, model),
            forgeUrl = forgeUrl,
        }
    end

    return {
        thumbnailUrl = nil,
        meshUrl = nil,
        forgeUrl = forgeUrl,
    }
end

---Payload sent to NUI so the catalog can lazy-load previews.
---@return table
function Preview.nuiConfig()
    local preview = config.preview or {}

    return {
        enabled = preview.enabled == true,
        provider = preview.provider or 'none',
        cacheMaxEntries = preview.cacheMaxEntries or 128,
        lazyRootMargin = preview.lazyRootMargin or '200px',
        forgeObjectUrl = preview.forgeObjectUrl or 'https://forge.plebmasters.de/objects/%s',
        thumbnailUrl = preview.thumbnailUrl,
        meshUrl = preview.meshUrl,
    }
end

return Preview
