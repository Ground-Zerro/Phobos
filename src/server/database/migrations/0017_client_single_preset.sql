UPDATE `clients_table` SET `preset_id` = `socks5_preset_id` WHERE `preset_id` IS NULL AND `socks5_preset_id` IS NOT NULL;
--> statement-breakpoint
ALTER TABLE `clients_table` DROP COLUMN `socks5_preset_id`;
