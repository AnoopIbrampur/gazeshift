import { defineConfig } from 'vitest/config';

// Served from https://anoopibrampur.github.io/gazeshift/ on GitHub Pages.
export default defineConfig({
  base: '/gazeshift/',
  build: { outDir: 'dist', target: 'es2020' },
  test: { environment: 'node', include: ['test/**/*.test.ts'] },
});
