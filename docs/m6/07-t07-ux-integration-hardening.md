# M6-T07 — Center administration UX, integration & product hardening

Implementation closeout from approved T07 design gate. Baseline: `8a0a698` (`chore(m6): harden security and organization isolation`).

## Scope delivered

### `/users` product contract (preserved)

- **Primary Owner:** summary card only; no lifecycle controls.
- **member + active:** change role, suspend, remove from center.
- **member + inactive:** change role, reactivate, remove from center.
- **member + locked:** access badge only; no lifecycle actions.
- **removed:** removed roster only; restore with role selection.
- Desktop table and mobile cards share `StaffLifecycleActions` (no forked business rules).

### Provisioning integration

- T03 orchestration unchanged; stable error UX including restore-oriented `removed_member_exists`.
- `revalidatePath("/users")` on success; idempotency and seat-full form disable unchanged.

### Lifecycle integration

- T05 RPCs unchanged; `revalidatePath("/users")` after successful mutations.
- Confirmation copy retains seat semantics (suspend retains seat; remove releases seat; restore consumes seat).

### Responsive behavior

- Mobile staff cards (`lg:hidden`) use the same lifecycle component as desktop.
- Playwright mobile smoke at 390×844 validates cards, locked staff, and one suspend mutation.

### Accessibility hardening

- Lifecycle triggers: `aria-expanded`, `aria-controls` (when panel open).
- Confirm panels: stable `id`, `role="region"`, `aria-labelledby`.
- Focus moves to the open panel; confirm buttons use `aria-busy` while submitting.
- Errors/success remain textual (`role="alert"` / `role="status"`).

### Server-action UX gate

- Shared `requireCenterAccountAdmin()` (`can('center_account.manage')` + session) on staff provisioning and lifecycle actions.
- DB RPC authorization remains authoritative; gate avoids unnecessary RPC calls for unauthorized callers.

### E2E additions

- **Mobile lifecycle smoke** — staff cards, locked staff without actions, suspend with badge refresh.
- **Full-seat restore** — org B at capacity; restore shows localized seat-limit error; no raw backend text; roster/seats unchanged.

### Verification

Full `npm run verify` exit **0** on closeout:

- Fresh Supabase db reset + seed; M0 **30/30** security; M6-T02 **25/25**, T03 **10/10**, T04 **10/10**, T05 **56/56**, T06 **18/18**
- i18n parity **1891/1891** keys; lint, typecheck, build PASS
- Playwright **196/196** (includes T07 mobile lifecycle + full-seat restore cases)

## Explicitly deferred (not T07)

- Auth ban/disable UI, Owner transfer, audit UI, teacher sync, legacy `user.read` removal.
- Modal dialog refactor for confirmations (inline regions retained).
- M6 milestone closeout (M6-T08).

## Final T07 verdict

**PASS — M6-T07 CLOSED** after full verification and closeout commit on `main`.
