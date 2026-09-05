---@class OxPropsConfig
---@field command string Chat command that opens the prop editor.
---@field permission string Ace permission required to use the editor. Must be an
---ace (e.g. 'admin'), not a principal (e.g. 'group.admin').
---@field maxProps number Maximum number of props that can exist at once.
---@field renderDistance number Distance in metres within which props are spawned.
---@field spawnDelay number Milliseconds between prop spawn batches when streaming in.
---@field gizmoMaxDistance number Maximum distance the editor can move a prop from where it was grabbed.
---@field persist boolean When true, props and sets are written to the `ox_props` tables
---and reloaded on restart. Requires oxmysql. Schema: sql/install.sql.
---@field preview OxPropsPreviewConfig Preview / Forge integration settings.

---@class OxPropsPreviewConfig
---@field enabled boolean When true, NUI lazy-loads thumbnail/mesh URLs from the provider.
---@field provider 'none' | 'forge' | 'url' Preview URL strategy.
---@field forgeObjectUrl string printf-style URL for opening a model on Plebmasters Forge.
---@field thumbnailUrl? string printf-style URL for thumbnails when provider is 'url'.
---@field meshUrl? string printf-style URL for glTF/GLB meshes when provider is 'url'.
---@field cacheMaxEntries number Max IndexedDB cache entries in the catalog NUI.
---@field lazyRootMargin string IntersectionObserver rootMargin for lazy loading.

return {
    command = 'props',
    permission = 'admin',

    maxProps = 500,
    renderDistance = 150.0,
    spawnDelay = 200,

    gizmoMaxDistance = 50.0,

    persist = false,

    preview = {
        enabled = false,
        provider = 'none',
        forgeObjectUrl = 'https://forge.plebmasters.de/objects/%s',
        thumbnailUrl = nil,
        meshUrl = nil,
        cacheMaxEntries = 128,
        lazyRootMargin = '200px',
    },
}
