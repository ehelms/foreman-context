---
name: foreman-ui-test
description: >-
  Write or update Foreman React UI tests with React Testing Library or
  Capybara. Use when adding a component or page, writing a Jest/RTL test,
  replacing Enzyme or snapshot tests, running plugin JS tests, or when the
  user mentions RTL, enzyme, shallow, IntegrationTestHelper, getByRole, or
  npm run test:plugins.
---

# Foreman UI Test

Write Foreman UI tests the way this project expects. Canonical detail lives in Foreman core: `developer_docs/ui-testing-guidelines.asciidoc`. Follow that file when it disagrees with memory.

## Choose RTL or Capybara

**RTL (Jest)** when the unit is a self-contained component: props in, visible UI out, no real API or routing flow.

**Capybara** when it is a full page/route, talks to the API, is a multi-step flow, or needs FactoryBot data. Examples: `test/integration/domain_test.rb`, `test/integration/domain_js_test.rb`.

## Run tests from Foreman core

Always run Jest from the Foreman core checkout, never from a plugin directory.

```bash
# Core
npm run test
npm run lint

# Plugin (from Foreman core). Name is the plugin directory, e.g. foreman_rh_cloud
npm run test:plugins <plugin-name>
npm run lint:plugins <plugin-name>
```

Plugin setup: `plugin/webpack/test_setup.js` (use `import 'foremanJSTestSetup'` to share core setup). Optional `plugin/jest.config.js` merges with core Jest config.

## RTL rules

File name: `*.test.js`, next to the component or in `__tests__/`.

Query in this order (what a screen reader sees first):

1. `getByRole`
2. `getByLabelText`
3. `getByText`
4. `getByPlaceholderText` / `getByDisplayValue`
5. `getByTestId` last

Use `userEvent` for clicks and typing. Use `fireEvent` only when `userEvent` cannot send the event.

Assert with `toBeInTheDocument()`. Assert on roles, accessible names, and visible text. Do not assert on CSS classes, DOM ids, or Enzyme wrappers.

Use `findBy*` / `waitFor` for async UI. Mark a test `async` only when it awaits. For `setTimeout` UI, use fake timers.

### Helpers and mocks

Core:

```js
import { rtlHelpers } from 'foremanReact/common/rtlTestHelpers';
const { renderWithStore, renderWithI18n, renderWithStoreAndI18n } = rtlHelpers;
```

Plugins import the same helpers via `foremanReact`. Do not copy store/i18n setup that `rtlTestHelpers` already provides.

Mock **API requests** only. Do not mock child components, selectors, or helpers unless there is no other way. If a child must be mocked, that child needs its own test.

Do not mock a child and then assert that the mock rendered. That tests the mock, not the component.

If the component uses `react-router-dom` `Link` or `useHistory`, wrap with `MemoryRouter`.

Write new tests with RTL (`rtlHelpers`, `getByRole`, `userEvent`). Use that instead of Enzyme: `IntegrationTestHelper` and `shallow` / `mount` / `render` from `enzyme` or `@theforeman/test`.

## Replacing Enzyme or snapshots

1. Check for deprecation first. Look for `deprecate(` or `deprecateObjectProperty(` from `DeprecationService` (`foremanReact/common/DeprecationService`). Also look for `@deprecated` and comments that it is scheduled for removal. If any of those are present, stop and leave the existing tests as they are.
2. Missing imports in this repository do not mean the component is unused. Plugins live in other repositories and import Foreman core via `foremanReact`. Delete a component and its tests only when it is plugin-local and that plugin has no remaining imports (including barrel `index.js` files and slot/fill registration). If it is core UI, or you cannot prove it is unused, skip deletion and convert the test instead.
3. If the component imports PF3 (`patternfly-react`), stop with an error. Remaining PF3 is expected only on deprecated UI. Leave the Enzyme test in place; this skill does not rewrite PF3.
4. Cover at least what the old test covered (text, conditionals, callbacks), using roles and behavior instead of wrapper internals.
5. Drop leftover `.snap` files and unused `__mocks__` / `jest.mock` calls.

## After writing tests

Run the smallest Jest invocation that covers the new files, from Foreman core. For a plugin, `npm run test:plugins <plugin-name>` (or equivalent Jest `--roots` from core if the plugin is not in the bundle).
