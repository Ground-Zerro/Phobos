PRAGMA journal_mode=WAL;
--> statement-breakpoint
CREATE TABLE `interfaces_table` (
	`name` text PRIMARY KEY NOT NULL,
	`device` text NOT NULL,
	`port` integer NOT NULL,
	`private_key` text NOT NULL,
	`public_key` text NOT NULL,
	`ipv4_cidr` text NOT NULL,
	`ipv6_cidr` text NOT NULL,
	`mtu` integer NOT NULL,
	`enabled` integer NOT NULL,
	`firewall_enabled` integer DEFAULT false NOT NULL,
	`obfuscator_ext_port` integer DEFAULT 51822 NOT NULL,
	`obfuscator_key` text DEFAULT '' NOT NULL,
	`obfuscator_masking` text DEFAULT 'STUN' NOT NULL,
	`obfuscator_idle` integer DEFAULT 300 NOT NULL,
	`obfuscator_dummy` integer DEFAULT 10 NOT NULL,
	`server_public_ip_v4` text DEFAULT '' NOT NULL,
	`server_public_ip_v6` text,
	`client_wg_local_port` integer DEFAULT 13255 NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `interfaces_table_port_unique` ON `interfaces_table` (`port`);
--> statement-breakpoint
CREATE TABLE `users_table` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`username` text NOT NULL,
	`password` text NOT NULL,
	`email` text,
	`name` text NOT NULL,
	`role` integer NOT NULL,
	`totp_key` text,
	`totp_verified` integer NOT NULL,
	`enabled` integer NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `users_table_username_unique` ON `users_table` (`username`);
--> statement-breakpoint

CREATE TABLE `hooks_table` (
	`id` text PRIMARY KEY NOT NULL,
	`pre_up` text NOT NULL,
	`post_up` text NOT NULL,
	`pre_down` text NOT NULL,
	`post_down` text NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`id`) REFERENCES `interfaces_table`(`name`) ON UPDATE cascade ON DELETE cascade
);--> statement-breakpoint

CREATE TABLE `user_configs_table` (
	`id` text PRIMARY KEY NOT NULL,
	`default_mtu` integer NOT NULL,
	`default_persistent_keepalive` integer NOT NULL,
	`default_dns` text NOT NULL,
	`default_allowed_ips` text NOT NULL,
	`host` text NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`id`) REFERENCES `interfaces_table`(`name`) ON UPDATE cascade ON DELETE cascade
);--> statement-breakpoint

CREATE TABLE `general_table` (
	`id` integer PRIMARY KEY DEFAULT 1 NOT NULL,
	`setup_step` integer NOT NULL,
	`session_password` text NOT NULL,
	`session_timeout` integer NOT NULL,
	`metrics_prometheus` integer NOT NULL,
	`metrics_json` integer NOT NULL,
	`metrics_password` text,
	`allow_insecure_http_login` integer DEFAULT false NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);--> statement-breakpoint

CREATE TABLE `clients_table` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`user_id` integer NOT NULL,
	`interface_id` text NOT NULL,
	`name` text NOT NULL,
	`ipv4_address` text NOT NULL,
	`ipv6_address` text NOT NULL,
	`pre_up` text DEFAULT '' NOT NULL,
	`post_up` text DEFAULT '' NOT NULL,
	`pre_down` text DEFAULT '' NOT NULL,
	`post_down` text DEFAULT '' NOT NULL,
	`private_key` text NOT NULL,
	`public_key` text NOT NULL,
	`pre_shared_key` text NOT NULL,
	`expires_at` text,
	`allowed_ips` text,
	`server_allowed_ips` text NOT NULL,
	`firewall_ips` text,
	`persistent_keepalive` integer NOT NULL,
	`mtu` integer NOT NULL,
	`dns` text,
	`server_endpoint` text,
	`enabled` integer NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users_table`(`id`) ON UPDATE cascade ON DELETE restrict,
	FOREIGN KEY (`interface_id`) REFERENCES `interfaces_table`(`name`) ON UPDATE cascade ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `clients_table_ipv4_address_unique` ON `clients_table` (`ipv4_address`);
--> statement-breakpoint
CREATE UNIQUE INDEX `clients_table_ipv6_address_unique` ON `clients_table` (`ipv6_address`);
--> statement-breakpoint
CREATE TABLE `install_links_table` (
	`id` integer PRIMARY KEY NOT NULL,
	`token` text NOT NULL,
	`expires_at` text NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`id`) REFERENCES `clients_table`(`id`) ON UPDATE cascade ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `install_links_table_token_unique` ON `install_links_table` (`token`);
--> statement-breakpoint
INSERT INTO `interfaces_table` (`name`, `device`, `port`, `private_key`, `public_key`, `ipv4_cidr`, `ipv6_cidr`, `mtu`, `enabled`)
VALUES ('wg0', 'eth0', 51820, '---default---', '---default---', '10.8.0.0/24', 'fdcc:ad94:bacf:61a4::cafe:0/112', 1420, 1);
--> statement-breakpoint
INSERT INTO `hooks_table` (`id`, `pre_up`, `post_up`, `pre_down`, `post_down`)
VALUES (
  'wg0',
  '',
  'iptables -t nat -A POSTROUTING -s {{ipv4Cidr}} -o {{device}} -j MASQUERADE; iptables -A INPUT -p udp -m udp --dport {{port}} -j ACCEPT; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -s {{ipv6Cidr}} -o {{device}} -j MASQUERADE; ip6tables -A INPUT -p udp -m udp --dport {{port}} -j ACCEPT; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -A FORWARD -o wg0 -j ACCEPT;',
  '',
  'iptables -t nat -D POSTROUTING -s {{ipv4Cidr}} -o {{device}} -j MASQUERADE; iptables -D INPUT -p udp -m udp --dport {{port}} -j ACCEPT; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -s {{ipv6Cidr}} -o {{device}} -j MASQUERADE; ip6tables -D INPUT -p udp -m udp --dport {{port}} -j ACCEPT; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -D FORWARD -o wg0 -j ACCEPT;'
);
--> statement-breakpoint
INSERT INTO `user_configs_table` (`id`, `default_mtu`, `default_persistent_keepalive`, `default_dns`, `default_allowed_ips`, `host`)
VALUES ('wg0', 1420, 0, '["8.8.8.8","2001:4860:4860::8888"]', '["0.0.0.0/0","::/0"]', '');
--> statement-breakpoint
INSERT INTO `general_table` (`setup_step`, `session_password`, `session_timeout`, `metrics_prometheus`, `metrics_json`, `allow_insecure_http_login`)
VALUES (1, hex(randomblob(256)), 3600, 0, 0, 0);
