-- Seed the mako (openai-image-proxy D1) `payday` tenant. Idempotent.
-- Apply from ~/Dev/rust/pixie:
--   npx wrangler d1 execute openai-image-proxy --remote --file <this>
-- SKU mapping: rc_product_prefix + pack_id = the App Store consumable id
--   (e.g. com.guitaripod.payday.credits. + starter = com.guitaripod.payday.credits.starter).

INSERT OR REPLACE INTO apps
  (app_id, name, enabled, rc_project_id, rc_product_prefix, apple_team_id, apple_app_bundle_id,
   enabled_capabilities, new_user_free_credits, premium_entitlement, default_chat_model)
VALUES
  ('payday', 'Pay Day', 1, 'proj2e2e82e3', 'com.guitaripod.payday.credits.', 'P4DQK6SRKR',
   'com.guitaripod.payday', 'chat.completion,peppol.send', 15, 'pro', 'gpt-5-mini');

-- AI line-item/reminder drafting goes through chat.completion (a few credits);
-- peppol.send is metered by the payday-worker against the same ledger.
INSERT OR REPLACE INTO capability_costs (app_id, capability, flat_credits, credit_multiplier) VALUES
  ('payday', 'chat.completion', 3, NULL),
  ('payday', 'peppol.send', 30, NULL);

INSERT OR REPLACE INTO credit_packs
  (app_id, pack_id, name, credits, bonus_credits, price_usd_cents, description, sort_order)
VALUES
  ('payday', 'starter',  'Starter',  30,  0,  299, '~1 Peppol send or a handful of AI drafts', 0),
  ('payday', 'regular',  'Regular',  110, 0,  999, 'Best for a steady invoicing month',         1),
  ('payday', 'propack',  'Pro Pack', 300, 0, 2499, 'Heavy senders',                              2),
  ('payday', 'business', 'Business', 650, 0, 4999, 'Agencies and high-volume B2B',               3);
