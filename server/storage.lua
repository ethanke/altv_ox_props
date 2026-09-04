local storage = {}

local schema = {
    sets = [[CREATE TABLE IF NOT EXISTS `ox_props_sets` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `name` VARCHAR(48) NOT NULL,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
    props = [[CREATE TABLE IF NOT EXISTS `ox_props` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `set_id` INT UNSIGNED NOT NULL,
        `model` VARCHAR(64) NOT NULL,
        `x` FLOAT NOT NULL,
        `y` FLOAT NOT NULL,
        `z` FLOAT NOT NULL,
        `rx` FLOAT NOT NULL DEFAULT 0,
        `ry` FLOAT NOT NULL DEFAULT 0,
        `rz` FLOAT NOT NULL DEFAULT 0,
        `owner` VARCHAR(64) DEFAULT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        INDEX `idx_ox_props_set` (`set_id`),
        CONSTRAINT `fk_ox_props_set`
            FOREIGN KEY (`set_id`) REFERENCES `ox_props_sets` (`id`)
            ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
}

---Creates the resource-owned tables and returns persisted rows.
---@return table sets, table props
function storage.load()
    MySQL.query.await(schema.sets)
    MySQL.query.await(schema.props)

    return MySQL.query.await('SELECT id, name, enabled FROM ox_props_sets') or {},
        MySQL.query.await('SELECT id, set_id, model, x, y, z, rx, ry, rz FROM ox_props') or {}
end

---@param prop OxProp
---@return integer?
function storage.insertProp(prop)
    return MySQL.insert.await(
        'INSERT INTO ox_props (set_id, model, x, y, z, rx, ry, rz, owner) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { prop.setId, prop.model, prop.coords.x, prop.coords.y, prop.coords.z, prop.rotation.x, prop.rotation.y, prop.rotation.z, prop.owner and tostring(prop.owner) or nil }
    )
end

---@param id integer
---@param coords vector3
---@param rotation vector3
function storage.updateProp(id, coords, rotation)
    MySQL.update.await('UPDATE ox_props SET x = ?, y = ?, z = ?, rx = ?, ry = ?, rz = ? WHERE id = ?', {
        coords.x, coords.y, coords.z, rotation.x, rotation.y, rotation.z, id,
    })
end

---@param id integer
function storage.deleteProp(id)
    MySQL.update.await('DELETE FROM ox_props WHERE id = ?', { id })
end

---@param name string
---@return integer?
function storage.createSet(name)
    return MySQL.insert.await('INSERT INTO ox_props_sets (name, enabled) VALUES (?, 1)', { name })
end

---@param id integer
---@param name string
function storage.renameSet(id, name)
    MySQL.update.await('UPDATE ox_props_sets SET name = ? WHERE id = ?', { name, id })
end

---@param id integer
---@param enabled boolean
function storage.setEnabled(id, enabled)
    MySQL.update.await('UPDATE ox_props_sets SET enabled = ? WHERE id = ?', { enabled and 1 or 0, id })
end

---@param id integer
function storage.deleteSet(id)
    MySQL.update.await('DELETE FROM ox_props_sets WHERE id = ?', { id })
end

return storage