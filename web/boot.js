// boot.js — a plain script with no imports. The only code on these pages that still runs when
// there is no signal.
//
// WHY THIS FILE EXISTS.
//
// Every screen's real code is a module whose first line imports the Supabase client from
// jsdelivr. When that fetch fails the browser discards the entire module graph in silence: no
// top bar, no error, nothing in the console the operator would ever be looking at.
//
// Measured on 2026-09-07 in headless Chrome against this repo:
//   · CDN blocked            → every screen was a bare grey rectangle, permanently. No text.
//   · throttled link, cold cache → 3.1 seconds of that same rectangle before the sign-in form
//                             appeared. Warm cache was still 1.8 seconds.
//
// A godown is precisely where the signal dies, and a blank screen is how chachu learns to stop
// opening this system. So the HTML now ships a real waiting state in #gate that needs no
// JavaScript at all, and this file is the timer that turns a wait that never ends into a
// sentence he can act on.
//
// Keep it a classic script. The moment this file imports anything it shares the failure it is
// here to report.

(function () {
  // Long enough that a slow-but-working link is never accused of being broken; short enough that
  // a man standing at a van is not left guessing. Measured worst case above was 3.1 s.
  var GIVE_UP_MS = 9000;

  function stillWaiting() {
    // The placeholder is removed the moment the real code paints either the sign-in form or a
    // screen. Checking the DOM rather than a "did the module load" flag on purpose: it also
    // catches a module that loaded fine and then hung on a request that never came back.
    var placeholder = document.querySelector('[data-djn-boot]');
    var app = document.getElementById('app');
    return !!placeholder && (!app || app.hidden);
  }

  function giveUp() {
    if (!stillWaiting()) return;
    var gate = document.getElementById('gate');
    if (!gate) return;

    var offline = (navigator.onLine === false);
    gate.innerHTML =
      '<div class="state state--error">' +
        '<div class="state__icon" aria-hidden="true">!</div>' +
        '<h2 class="state__title">' +
          (offline ? 'This phone has no internet' : 'The app could not start') +
        '</h2>' +
        '<p class="state__body">' +
          (offline
            ? 'The screens need a connection to load. Move to where there is signal and try again.'
            : 'It could not reach the internet to load. Check the signal, then try again.') +
        '</p>' +
        '<button class="btn btn--primary" id="djn-boot-retry" type="button">Try again</button>' +
      '</div>';
    gate.hidden = false;
    var btn = document.getElementById('djn-boot-retry');
    if (btn) btn.addEventListener('click', function () { location.reload(); });
    btn && btn.focus();
  }

  setTimeout(giveUp, GIVE_UP_MS);

  // If the connection comes back while he is staring at the failure, retry without a tap.
  window.addEventListener('online', function () {
    if (document.getElementById('djn-boot-retry')) location.reload();
  });
})();
