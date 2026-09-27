// Self-contained on purpose: a config that reaches for @eslint/js would need a
// package.json and node_modules, and this repo keeps its javascript free of
// both. The list below is eslint's own recommended set, read from its rule
// metadata rather than remembered, plus the handful this project adds.

const recommended = {
  "constructor-super": "error",
  "for-direction": "error",
  "getter-return": "error",
  "no-async-promise-executor": "error",
  "no-case-declarations": "error",
  "no-class-assign": "error",
  "no-compare-neg-zero": "error",
  "no-cond-assign": ["error", "always"],
  "no-const-assign": "error",
  "no-constant-binary-expression": "error",
  "no-constant-condition": "error",
  "no-control-regex": "error",
  "no-debugger": "error",
  "no-delete-var": "error",
  "no-dupe-args": "error",
  "no-dupe-class-members": "error",
  "no-dupe-else-if": "error",
  "no-dupe-keys": "error",
  "no-duplicate-case": "error",
  "no-empty": "error",
  "no-empty-character-class": "error",
  "no-empty-pattern": "error",
  "no-empty-static-block": "error",
  "no-ex-assign": "error",
  "no-extra-boolean-cast": "error",
  "no-fallthrough": "error",
  "no-func-assign": "error",
  "no-global-assign": "error",
  "no-import-assign": "error",
  "no-invalid-regexp": "error",
  "no-irregular-whitespace": "error",
  "no-loss-of-precision": "error",
  "no-misleading-character-class": "error",
  "no-new-native-nonconstructor": "error",
  "no-nonoctal-decimal-escape": "error",
  "no-obj-calls": "error",
  "no-octal": "error",
  "no-prototype-builtins": "error",
  "no-redeclare": "error",
  "no-regex-spaces": "error",
  "no-self-assign": "error",
  "no-setter-return": "error",
  "no-shadow-restricted-names": "error",
  "no-sparse-arrays": "error",
  "no-this-before-super": "error",
  "no-unassigned-vars": "error",
  "no-undef": "error",
  "no-unexpected-multiline": "error",
  "no-unreachable": "error",
  "no-unsafe-finally": "error",
  "no-unsafe-negation": "error",
  "no-unsafe-optional-chaining": "error",
  "no-unused-labels": "error",
  "no-unused-private-class-members": "error",
  "no-unused-vars": ["error", { args: "after-used", caughtErrors: "none" }],
  "no-useless-assignment": "error",
  "no-useless-backreference": "error",
  "no-useless-catch": "error",
  "no-useless-escape": "error",
  "no-with": "error",
  "preserve-caught-error": "error",
  "require-yield": "error",
  "use-isnan": "error",
  "valid-typeof": ["error", { requireStringLiterals: true }],
};

// Beyond recommended, each earned by a bug this codebase has shipped: a stale
// comparison, a name shadowing another, a value read before it was defined.
const alsoErrors = {
  eqeqeq: ["error", "always"],
  "no-self-compare": "error",
  "no-shadow": "error",
  "no-unmodified-loop-condition": "error",
  "no-unreachable-loop": "error",
  "no-use-before-define": ["error", { functions: false }],
  "require-atomic-updates": "error"
};

const rules = Object.assign({}, recommended, alsoErrors);

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
    //
    // no-implicit-globals stays off here: what QML reaches through `Model.` are
    // the declarations at its top level, so they are its interface rather than
    // leaked globals, and the rule would reject every one.
    files: ["Model.js"],
    languageOptions: {
      ecmaVersion: 2015,
      sourceType: "script",
      globals: { module: "writable" }
    },
    linterOptions,
    rules: rules
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
    rules: Object.assign({}, rules, { "no-implicit-globals": "error" })
  }
];
