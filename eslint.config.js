import js from '@eslint/js';
import svelte from 'eslint-plugin-svelte';
import { defineConfig } from 'eslint/config';
import globals from 'globals';
import ts from 'typescript-eslint';
import svelteConfig from './apps/dashboard/svelte.config.js';

export default defineConfig(
  {
    ignores: [
      '**/node_modules/',
      '**/build/',
      '**/.svelte-kit/',
      '**/.wrangler/',
      '**/test-results/',
      '**/playwright-report/',
      '.tools/',
      'packages/shared/src/database.types.ts',
      'supabase/functions/_shared/shared/',
    ],
  },
  js.configs.recommended,
  ts.configs.recommended,
  svelte.configs.recommended,
  {
    languageOptions: { globals: { ...globals.browser, ...globals.node } },
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    },
  },
  {
    files: ['**/*.svelte', '**/*.svelte.ts'],
    languageOptions: { parserOptions: { parser: ts.parser, extraFileExtensions: ['.svelte'], svelteConfig } },
  },
);
