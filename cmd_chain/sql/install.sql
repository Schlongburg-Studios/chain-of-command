-- Chain of Command (cmd_chain) v1.1.0
-- The resource also creates these tables on start; running this file is optional.
-- Rank is NOT stored here. It always comes from the framework job grade.

CREATE TABLE IF NOT EXISTS `cmd_chain_members` (
  `citizenid`  VARCHAR(50) NOT NULL,
  `dept`       VARCHAR(50) NOT NULL,
  `callsign`   VARCHAR(16) NULL DEFAULT NULL,
  `divisions`  JSON NULL DEFAULT NULL,
  `hired_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`, `dept`),
  UNIQUE KEY `uq_dept_callsign` (`dept`, `callsign`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmd_chain_audit` (
  `id`               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `dept`             VARCHAR(50) NOT NULL,
  `actor_citizenid`  VARCHAR(50) NULL DEFAULT NULL, -- NULL = server console or a change made outside cmd_chain
  `target_citizenid` VARCHAR(50) NULL DEFAULT NULL, -- NULL for rank-structure changes
  `action`           VARCHAR(32) NOT NULL,
  `old_value`        TEXT NULL DEFAULT NULL,
  `new_value`        TEXT NULL DEFAULT NULL,
  `created_at`       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_dept_time` (`dept`, `created_at`),
  KEY `idx_target` (`target_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- v1.1: rank structure edited in game (only used when Config.Structure.editable = true).
-- These are rank DEFINITIONS (name, pay, capabilities per grade). A player's rank is still
-- their framework job grade and is never stored here.
CREATE TABLE IF NOT EXISTS `cmd_chain_ranks` (
  `dept`       VARCHAR(50) NOT NULL,
  `grade`      SMALLINT UNSIGNED NOT NULL,
  `name`       VARCHAR(50) NOT NULL,
  `payment`    INT UNSIGNED NOT NULL DEFAULT 0,
  `caps`       JSON NULL DEFAULT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`dept`, `grade`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Upgrading from v1.0: structure changes have no target player.
ALTER TABLE `cmd_chain_audit` MODIFY `target_citizenid` VARCHAR(50) NULL DEFAULT NULL;
