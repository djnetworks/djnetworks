-- 0020_correction_reason_required.sql
-- A correction must say why.
--
-- 0019 built the mechanism and left the sentence optional. That is backwards: the mechanism can
-- walk a piece's history back one visible row at a time, and the ONLY thing that makes that safe
-- rather than merely auditable is that each step carries a reason somebody wrote. A trail that
-- records "this was undone" and nothing about what happened is a trail nobody can act on.
--
-- The whole change is one guard added to fn_correction_matches_target. The rest of the function is
-- reproduced unchanged, because create-or-replace has no other shape and a diff of this file
-- against 0019 shows exactly the eight lines that are new.

create or replace function fn_correction_matches_target()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  t          movement%rowtype;
  v_tip      uuid;
  v_left     int;
  v_already  int;
begin
  if new.movement_type <> 'correction' then
    -- Only a correction may name a target. Any other row pointing at one would read as a
    -- correction to anyone scanning the column and would be counted as neither.
    if new.corrects_movement_id is not null then
      raise exception
        'only a correction may name the movement it undoes; this is a %. Record the mistake as a correction, or leave corrects_movement_id empty.',
        new.movement_type;
    end if;
    return new;
  end if;

  if new.corrects_movement_id is null then
    raise exception
      'a correction must name the movement it undoes (corrects_movement_id). A correction that floats free cannot be netted out of anything, and leaves nobody able to say why a piece is where the screen says it is.';
  end if;

  -- ---- the reason ----
  --
  -- MANDATORY, and enforced here rather than in the screen that happens to write it. A correction
  -- can walk a piece's history back one row at a time; the only thing that makes that safe is that
  -- every step says why, in a sentence a person wrote. Without it the mechanism is a silent undo
  -- with an audit trail that records that something was undone and nothing about what happened.
  --
  -- 0019 asked for the reason in a prompt and accepted whatever came back, including nothing at
  -- all if the row was written by anything other than return.html. The proof that the sentence
  -- earns its place is 0019's own worked example: "return (CORRECTED: the sub never left the
  -- hall)" is a history somebody can read three weeks later; "return (CORRECTED)" is not.
  --
  -- The eight-character floor is a floor, not a quality test. It stops the empty string, a space
  -- and a full stop; it cannot stop "asdfghjk" and does not pretend to. "not back" is eight and
  -- passes, which is the shortest thing anybody would actually write.
  if new.notes is null or length(btrim(new.notes)) < 8 then
    raise exception
      'a correction must say WHY, in notes — at least a few words. This is the only record of what actually happened: the movement it undoes stays in the history for ever, flagged, and the reason is the sentence next to it that somebody reads three weeks later when a customer disputes a return. "not back" is enough; nothing is not.';
  end if;

  select * into t from movement where id = new.corrects_movement_id;
  if t.id is null then
    raise exception 'the movement this correction names does not exist.';
  end if;

  -- A correction is not itself a movement of goods and has nothing to undo.
  if t.movement_type = 'correction' then
    raise exception
      'a correction cannot correct another correction. If the first correction was itself a mistake, record the movement again as a fresh entry — that is what actually happened.';
  end if;

  select count(*)::int into v_already
  from movement c
  where c.movement_type = 'correction' and c.corrects_movement_id = new.corrects_movement_id;
  if v_already > 0 then
    raise exception
      'that movement has already been corrected. Correcting it twice would net it out twice and drive the arithmetic below zero.';
  end if;

  -- ---- the tip test ----
  if t.unit_id is not null then
    -- Numbered piece: the tip is that piece's own last effective movement. Scoping per piece is
    -- what makes "All 6 back" correctable at all — six returns written in one transaction share a
    -- created_at, but each belongs to a different piece, so none of them ties with another.
    select e.id into v_tip
    from v_movement_effective e
    where e.unit_id = t.unit_id
    order by e.moved_on desc, e.created_at desc, e.id desc
    limit 1;

    -- A piece must never be left with no movement at all: intake writes the opening one precisely
    -- so that no unit exists without a location (docs/structure.md, form 3). Correcting the last
    -- one standing would make v_unit_location return no row and v_unit_status read
    -- `not_recorded` — a piece that exists and is nowhere.
    select count(*)::int into v_left from v_movement_effective e where e.unit_id = t.unit_id;
    if v_left <= 1 then
      raise exception
        'this is the only movement left on that piece, and correcting it would leave the piece with no location at all. Record where it actually is instead — an intake or a transfer.';
    end if;
  else
    -- Counted and used-up stock (rule 13): there are no piece numbers, so the tip is scoped to the
    -- product on the same job. Pool arithmetic is a SUM and is order-independent, so nothing here
    -- is ambiguous the way a unit's span is — the rule is narrower because it only has to stop the
    -- ledger becoming editable, not to keep a span unambiguous.
    select e.id into v_tip
    from v_movement_effective e
    where e.product_id = t.product_id
      and e.unit_id is null
      and e.order_id is not distinct from t.order_id
    order by e.moved_on desc, e.created_at desc, e.id desc
    limit 1;
  end if;

  if v_tip is distinct from t.id then
    raise exception
      'only the most recent movement can be corrected, and that one is not it — something has happened since. Correcting mid-history would leave every date span and every location derived from it ambiguous. Undo what came after first, or record what actually happened as a new movement.';
  end if;

  -- ---- what the correction row itself is ----
  -- Set, not checked. A correction annotates one movement; every one of these values is already
  -- knowable from the target, and asking a caller to repeat them is asking it to get one wrong.
  new.unit_id    := t.unit_id;
  new.product_id := t.product_id;
  new.order_id   := t.order_id;
  new.qty        := t.qty;          -- descriptive only; every view ignores a correction's numbers
  new.from_kind  := 'none';
  new.from_id    := null;
  new.to_kind    := 'none';
  new.to_id      := null;
  return new;
end $$;

-- The trigger already points at this function by name (0019) and is not recreated.
