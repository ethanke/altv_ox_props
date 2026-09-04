-- ox_props schema
-- Idempotent: safe to run multiple times. Owned by the ox_props resource.
-- Rollback: DROP TABLE ox_props; DROP TABLE ox_props_sets; (destroys all placed props)

CREATE TABLE IF NOT EXISTS `ox_props_sets` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(48) NOT NULL,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ox_props` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- The Global set (id 0) is created by the resource at runtime and is not
-- stored in the table; AUTO_INCREMENT starts at 1 for user-created sets.
