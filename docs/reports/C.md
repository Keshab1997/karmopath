Batch 2: C ready (bbdfb64)
Changed: admin/README.md, tools/feed/validate.py, tests/feed/test_validate.py, tests/feed/admin_ui_flow_test.js; actual app.js fake-DOM event-flow coverage, validator URL/UTF-8/type hardening, fixture parity.
Evidence: `python3 tool/preflight.py` PASS; Python unittest discovery 20 passed; `node --check` all four JS files PASS; Node behavior/UI-flow suite 17 passed, including Python validation of exported candidate. Browser automation NOT RUN (no browser binary available).
Not touched: main/A-B base, shared files, dependencies/workflows/secrets, production routes/publication; no CI/build/release.
Next: Captain review and browser smoke when available; no job was published.
