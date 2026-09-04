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

return {
    command = 'props',
    permission = 'admin',

    maxProps = 500,
    renderDistance = 150.0,
    spawnDelay = 200,

    gizmoMaxDistance = 50.0,

    persist = false,
}
