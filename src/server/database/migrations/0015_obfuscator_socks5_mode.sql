ALTER TABLE `obfuscator_presets_table` ADD `mode` text DEFAULT 'WIREGUARD' NOT NULL;
--> statement-breakpoint
ALTER TABLE `obfuscator_presets_table` ADD `media_ssrc` integer;
--> statement-breakpoint
ALTER TABLE `obfuscator_presets_table` ADD `client_local_port` integer DEFAULT 1080 NOT NULL;
