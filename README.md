# Mahrjan System

Van sales app and office portal for Mahrjan General Trading (Al Quoz MGAZ, Ajman MGT).

- **Frontend:** `index.html` (single page, no build step), hosted on GitHub Pages.
- **Backend:** Supabase (PostgreSQL). All business rules live in the database:
  `post_loading`, `post_return`, `save_requirement`, `save_expenses`, `save_collections`,
  `import_sales`, `settle_day`, `close_day`, `reopen_day`.
- **Login:** staff log in with their username (e.g. `rahees`) and password. The Supabase login
  email is `<username>@mahrjan.app`; it links to the staff record automatically.

## Daily flow
Requirement → Loading → Return → Sales import (iTrade export) → Settle cash → Close day.

- Excess / short = total return − (load − sale + GRV)
- Cash to hand over = cash sales − cash returns + collections − expenses
- Quantities: finished goods in packs, raw egg in pieces.
- A closed day cannot be changed; only ADMIN can reopen it, with a reason.

The key in `index.html` is the Supabase **publishable** key, which is meant to be public.
Data is protected by row-level security and role checks in the database functions.
