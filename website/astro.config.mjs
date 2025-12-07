// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// https://astro.build/config
export default defineConfig({
  site: 'https://joegaebel.github.io',
  base: '/sena-firmware-archive',
  integrations: [sitemap()],
});
