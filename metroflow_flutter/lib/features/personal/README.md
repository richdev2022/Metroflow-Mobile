# Personal Features (Dormant) — Mobile

`bills_screen.dart` and `savings_screen.dart` are **Personal Metricorex**
screens, not business features. They were moved here out of the routed app
until the Personal app commences.

They are no longer imported by `main.dart` (so they are not part of the
business app bundle), their routes (`/main/bills`, `/main/savings`), drawer
entries and plan-card knobs were removed.

To reactivate when the Personal app ships:

1. Move the screens back under `lib/screens/` (or import from here).
2. Re-add the routes in `lib/main.dart`:
   ```dart
   GoRoute(
     path: 'bills',
     builder: (context, state) => const BillsScreen(),
   ),
   GoRoute(
     path: 'savings',
     builder: (context, state) => const SavingsScreen(),
   ),
   ```
3. Re-add the drawer entries in `lib/screens/main_screen.dart` (a Personal
   section) and the plan knobs in `lib/models/plan.dart` +
   `lib/screens/subscription_screen.dart` (`bills_enabled`, `max_bills_per_day`,
   `bill_fee_discount_percent`, `savings_enabled`, `max_savings_vaults`,
   `savings_break_fee_discount_percent` are still served by the API).
4. Re-add the api methods (see the backend personal README for the endpoint
   list): `/bills/*` and `/savings/vaults/*`.

The matching backend code lives at
`metroflow-backend/server/features/personal/` (see its README); the web
counterparts live at `metroflow-app/client/features/personal/`.
