// Self-contained on purpose: a config that reaches for @eslint/js would need a
// package.json and node_modules, and this repo keeps its javascript free of
// both. Every rule is named here, so what the gate enforces is readable without
// chasing what a shared preset expands to this month.

const correctness = {
  "no-cond-assign": ["error", "always"],
  "no-constant-binary-expression": "error",
  "no-constant-condition": "error",
  "no-dupe-args": "error",
  "no-dupe-else-if": "error",
  "no-dupe-keys": "error",
  "no-duplicate-case": "error",
  "no-empty": "error",
  "no-fallthrough": "error",
  "no-func-assign": "error",
  "no-irregular-whitespace": "error",
  "no-loss-of-precision": "error",
  "no-self-assign": "error",
  "no-self-compare": "error",
  "no-sparse-arrays": "error",
  "no-unmodified-loop-condition": "error",
  "no-unreachable": "error",
  "no-unreachable-loop": "error",
  "no-unsafe-negation": "error",
  "no-unsafe-optional-chaining": "error",
  "no-unused-private-class-members": "error",
  "no-unused-vars": ["error", { args: "after-used", caughtErrors: "none" }],
  "no-use-before-define": ["error", { functions: false }],
  "require-atomic-updates": "error",
  "use-isnan": "error",
  "valid-typeof": ["error", { requireStringLiterals: true }],

  eqeqeq: ["error", "always"],
  "no-undef": "error",
  "no-redeclare": "error",
  "no-shadow": "error"
};

// A directive that no longer silences anything is a claim about the code that
// has stopped being true, so it fails rather than lingering.
const linterOptions = { reportUnusedDisableDirectives: "error" };

module.exports = [
  {
    ignores: ["priv/**", "tests/fixtures/**"]
  },
  {
    // Model.js loads in Qt's javascript engine and in node, from one file, so it
    // is a script rather than a module. The ceiling is ES2015: the bar glyphs
    // are code-point escapes, which ES5 cannot parse, and syntax newer than that
    // has no business arriving here untested against the engine that ships it.
    files: ["Model.js"],
    languageOptions: {
      ecmaVersion: 2015,
      sourceType: "script",
      globals: { module: "writable" }
    },
    linterOptions,
    // A javascript resource has no exports: what QML reaches through `Model.`
    // are the declarations at its top level, so they are the interface rather
    // than leaked globals, and no-implicit-globals would reject every one.
    rules: correctness
  },
  {
    files: ["tests/**/*.js", "eslint.config.js"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "commonjs",
      globals: {
        require: "readonly",
        module: "writable",
        console: "readonly",
        process: "readonly",
        __dirname: "readonly"
      }
    },
    linterOptions,
    rules: Object.assign({}, correctness, { "no-implicit-globals": "error" })
  }
];
