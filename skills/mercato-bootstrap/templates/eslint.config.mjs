import coreWebVitals from 'eslint-config-next/core-web-vitals'
import typescript from 'eslint-config-next/typescript'

// Flat config for Next 16 (`next lint` was removed; `yarn lint` runs `eslint .`).
// The empty preset ships no eslint config, so we compose eslint-config-next's flat presets.
const config = [
  {
    ignores: [
      '.next/**',
      '.mercato/**',
      'node_modules/**',
      'dist/**',
      'coverage/**',
      'public/**',
      'next-env.d.ts',
    ],
  },
  ...coreWebVitals,
  ...typescript,
  {
    // The empty-preset app shell (vendored by create-mercato-app) trips the newer
    // react-hooks v6 rules and a couple of `any`s. It is upstream scaffold code, not
    // ours, so relax those to warnings HERE ONLY — our own modules (src/modules/**,
    // src/lib/**) keep the strict defaults, incl. no-explicit-any as an error.
    files: ['src/app/**', 'src/components/**'],
    rules: {
      'react-hooks/set-state-in-effect': 'warn',
      'react-hooks/immutability': 'warn',
      'react-hooks/rules-of-hooks': 'warn',
      'react-hooks/refs': 'warn',
      'react-hooks/static-components': 'warn',
      '@typescript-eslint/no-explicit-any': 'warn',
    },
  },
]

export default config
