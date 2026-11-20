# Mahrjan System — install and run plan

The current van sales app, sales portal and Google Sheets stay exactly as they are.
The new system runs alongside them until its numbers match, then takes over.

## 1. Logins (Supabase > Authentication > Users > Add user > Create new user)
Email = `<staff name>@mahrjan.app` (lower case), tick **Auto Confirm User**.
The login links to the staff record automatically. Packers do not need logins.

| Role | Staff | Email |
|---|---|---|
| Admin | MUSTHAFFIR | musthaffir@mahrjan.app (done) |
| Accountant | RAHEES (Al Quoz), JABIR (Ajman), HISHAM (both) | rahees@ / jabir@ / hisham@mahrjan.app |
| Receiver | SHAMEEM, SANTHOSH (Al Quoz) | shameem@ / santhosh@mahrjan.app |
| Salesman | SHAREEF, KAREEM, SHINOJ, MUNAVAR, ASIN, FAISAL, RAMSHAD (Al Quoz); SHAFEEK, IBRAHIM, IRFAN, ANSAR (Ajman) | <name>@mahrjan.app |
| Viewer | FAIS, UNAIS, AFEEF, RAHOOF, BINOY, AKHIL | <name>@mahrjan.app |

Staff log in with just the name (e.g. `rahees`) and their password.

## 2. Parallel run (one week)
Every day, in addition to the current process:
1. Receiver posts the board in **Loading** (salesman, van, start KM, temperature, items).
2. Receiver posts **Return** after unloading (good / damage / expiry / waste / FOC, end KM, cartons).
3. Accountant exports the iTrade *Periodical Sales Detailed Report* for the day and uploads it in **Sales import**.
4. Accountant opens the van day in **Van days**: checks expenses and collections, enters cash counted, **Settle**, then **Close** (reason needed for any excess / short).
5. Compare with the store issue sheet (VAN DAY / VAN STOCK). Any difference = report it, fix, re-run.

## 3. Go-live
When a full week matches: stop entering the board / return in the old app, keep the old portal read-only for history.

## 4. Backups (Supabase Free has none)
1. Create a **private** GitHub repository `mahrjan-backup`.
2. Copy `docs/backup-repo/.github/workflows/nightly-backup.yml` into it at the same path.
3. Supabase > **Connect** > *Session pooler* > copy the URI and put your database password in it.
4. In `mahrjan-backup` > Settings > Secrets and variables > Actions > **New repository secret**:
   name `SUPABASE_DB_URL`, value = that URI.
5. Actions tab > *Nightly database backup* > **Run workflow** once to test. After that it runs every night at 02:30 and keeps 30 days.

## 5. Keep Supabase awake
Free projects pause after 7 days with no activity. Daily use keeps it awake. Move to the Pro plan before the system is the only record.

## 6. Rules built into the database
- Excess / short = total return − (load − sale + GRV); reason required at close.
- Cash to hand over = cash sales − cash returns + collections − expenses.
- Finished goods counted in packs, raw egg in pieces (tray = 30, quail tray = 18).
- A customer moves to another salesman only when that salesman invoices them.
- New customers in an iTrade export are added automatically.
- Closed days are locked; only ADMIN can reopen, with a reason. Every change is in the audit log.
