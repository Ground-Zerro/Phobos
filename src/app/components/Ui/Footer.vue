<template>
  <footer>
    <p class="m-10 text-center text-xs text-gray-300 dark:text-neutral-600">
      <a
        class="hover:underline"
        target="_blank"
        href="https://github.com/Ground-Zerro/Phobos"
        >Phobos</a
      >
      - secure WireGuard VPN with traffic obfuscation © {{ phobosYears }} by
      Ground_Zerro ·
      <a
        class="hover:underline"
        target="_blank"
        href="https://boosty.to/ground_zerro"
        >{{ $t('layout.donate') }}</a
      >
      <br />
      <strong>based on</strong>
      <br />
      <a
        class="hover:underline"
        target="_blank"
        href="https://github.com/wg-easy/wg-easy"
        >WireGuard Easy</a
      >
      ({{ globalStore.information?.currentRelease }}) © 2021-{{ currentYear }}
      by
      <a
        class="hover:underline"
        target="_blank"
        href="https://emile.nl/?ref=wg-easy"
        >Emile Nijssen</a
      >
      is licensed under
      <a
        class="hover:underline"
        target="_blank"
        href="https://opensource.org/license/agpl-v3"
        >AGPL-3.0-only</a
      >
      ·
      <a
        class="hover:underline"
        href="https://github.com/wg-easy/wg-easy#donate"
        target="_blank"
        >{{ $t('layout.donate') }}</a
      >
      <br />
      <strong>and</strong>
      <br />
      <a
        class="hover:underline"
        target="_blank"
        href="https://github.com/ClusterM/wg-obfuscator"
        >wg-obfuscator</a
      >,
      <a
        class="hover:underline"
        target="_blank"
        href="https://github.com/ClusterM/wg-obfuscator-android"
        >wg-obfuscator-android</a
      >
      © {{ obfuscatorYears }} by ClusterM licensed under GNU General Public
      License v3.0 ·
      <a
        class="hover:underline"
        target="_blank"
        href="https://boosty.to/cluster"
        >{{ $t('layout.donate') }}</a
      >
    </p>
  </footer>
</template>

<script lang="ts" setup>
const globalStore = useGlobalStore();
const currentYear = new Date().getFullYear();
const phobosYears = currentYear === 2026 ? '2026' : `2026-${currentYear}`;
const obfuscatorYears = currentYear === 2025 ? '2025' : `2025-${currentYear}`;
</script>
