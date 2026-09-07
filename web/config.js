// config.js — Supabase connection for the static frontend.
//
// ===========================================================================
//  THE KEY BELOW IS PUBLIC BY DESIGN, AND THIS FILE IS COMMITTED ON PURPOSE.
//
//  It is a publishable key. It ships inside the page, the browser must be able
//  to read it, and anyone who opens View Source has it. It is not a secret,
//  and there is no version of this system where it becomes one. Putting it in
//  .env would not hide it — .env is for things the browser must NEVER see, and
//  this is the opposite of that.
//
//  ROW LEVEL SECURITY IS THE ONLY THING PROTECTING THE DATA.
//
//  Every table has RLS on, with one policy: an authenticated user may do
//  everything, anonymous traffic may do nothing. So this key on its own opens
//  nothing at all — it lets the page ask, and the answer is "no rows" until
//  somebody signs in. If a policy is ever loosened to make a screen work, that
//  table is published to the internet the same day. See CLAUDE.md, "The
//  publishable key is public".
//
//  The customer portal is NOT built on anonymous table access, for exactly
//  this reason. It reads through a security definer function keyed on a
//  per-customer token.
//
//  NEVER put the service_role key or the sb_secret_ key in this file, or in
//  any file under web/. Those bypass RLS entirely.
// ===========================================================================

export const SUPABASE_URL = 'https://hjidocpqcrfbjucvqggu.supabase.co';
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_HKJ31sfuEUv8bX6aHflL4w_UkKfzgti';

// Bumped on every deploy so staff do not sit on a cached old version.
// See the djn-deploy skill: a fix that "isn't showing up" is this, nine times in ten.
export const APP_VERSION = '2026-09-08-12';
