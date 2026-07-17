PRAGMA foreign_keys=OFF;
--> statement-breakpoint
ALTER TABLE `clients_table` ADD COLUMN `socks5_preset_id` integer REFERENCES `obfuscator_presets_table`(`id`) ON UPDATE cascade ON DELETE set null;
--> statement-breakpoint
ALTER TABLE `clients_table` ADD COLUMN `socks5_login` text;
--> statement-breakpoint
ALTER TABLE `clients_table` ADD COLUMN `socks5_password` text;
--> statement-breakpoint
PRAGMA foreign_keys=ON;
