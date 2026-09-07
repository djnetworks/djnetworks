/**
 * DataSync.gs — paste into the mirror Google Sheet (Extensions → Apps Script).
 *
 * Pulls every mirrored tab from the sheet-mirror Edge Function and FULL-REPLACES each one.
 *
 * ONE DIRECTION ONLY. This script reads from the database and writes to the Sheet. It never writes
 * back. If the Sheet could write to the database the two would disagree and there would be no way
 * to know which was right — see the djn-sheet-sync skill. The bulk catalogue importer is the other
 * lane and is a separate, validated thing; it is not this file.
 *
 * SETUP
 *   1. Extensions → Apps Script, paste this in, save.
 *   2. Project Settings → Script Properties, add:
 *        MIRROR_URL    https://<project-ref>.supabase.co/functions/v1/sheet-mirror
 *        MIRROR_TOKEN  the same value set as MIRROR_TOKEN on the Edge Function
 *      Script Properties, not constants in this file: a Sheet gets shared, and a token pasted into
 *      the code goes with it.
 *   3. Run syncNow() once and grant the permission prompt.
 *   4. Optional: installTrigger() for an hourly refresh.
 *
 * A NOTE ON FORMULAS, learned the hard way on this business's earlier spreadsheets: ARRAYFORMULA
 * does NOT survive an xlsx → Sheets import — every such cell becomes #ERROR!, confirmed twice. If
 * you add derived columns to these tabs, write them in Sheets directly, and put them on a SEPARATE
 * tab. Anything in a mirrored tab is wiped on the next sync, by design.
 */

function syncNow() {
  var props = PropertiesService.getScriptProperties();
  var url = props.getProperty('MIRROR_URL');
  var token = props.getProperty('MIRROR_TOKEN');

  if (!url || !token) {
    SpreadsheetApp.getUi().alert(
      'Not configured yet.\n\nProject Settings → Script Properties needs MIRROR_URL and ' +
      'MIRROR_TOKEN before this can run.');
    return;
  }

  var res = UrlFetchApp.fetch(url, {
    method: 'get',
    headers: { 'x-mirror-token': token },
    muteHttpExceptions: true,
  });

  if (res.getResponseCode() !== 200) {
    SpreadsheetApp.getUi().alert(
      'The mirror could not be read (HTTP ' + res.getResponseCode() + ').\n\n' +
      res.getContentText().slice(0, 400));
    return;
  }

  var payload = JSON.parse(res.getContentText());
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var written = [];

  Object.keys(payload.tabs).forEach(function (name) {
    var rows = payload.tabs[name];
    var sheet = ss.getSheetByName(name) || ss.insertSheet(name);

    // FULL REPLACE. Clearing first is what stops a deleted row living on in the Sheet for ever.
    sheet.clear();
    if (rows.length) {
      sheet.getRange(1, 1, rows.length, rows[0].length).setValues(rows);
      sheet.setFrozenRows(1);
      sheet.getRange(1, 1, 1, rows[0].length).setFontWeight('bold');
    }
    written.push(name + ' (' + Math.max(rows.length - 1, 0) + ')');
  });

  // A visible stamp, because a mirror that silently stops updating is worse than one that is
  // obviously stale — the numbers look current either way.
  var meta = ss.getSheetByName('_sync') || ss.insertSheet('_sync');
  meta.clear();
  meta.getRange(1, 1, 4, 2).setValues([
    ['Last synced', new Date()],
    ['Generated at (server)', payload.generated_at],
    ['Tabs written', written.join(', ')],
    ['Direction', 'Read-only mirror OUT of the database. Edits made here are overwritten.'],
  ]);
  meta.getRange(1, 1, 4, 1).setFontWeight('bold');
  meta.autoResizeColumns(1, 2);
}

function installTrigger() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'syncNow') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('syncNow').timeBased().everyHours(1).create();
  SpreadsheetApp.getUi().alert('Hourly sync installed.');
}

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu("DJ Network's")
    .addItem('Sync now', 'syncNow')
    .addItem('Install hourly sync', 'installTrigger')
    .addToUi();
}
