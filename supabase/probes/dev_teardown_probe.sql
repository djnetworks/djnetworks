-- dev_teardown · THE REFUSAL MUST ACTUALLY FIRE.
--
-- dev_teardown.sql promises to stop, touching nothing, if the database holds a single row the seed
-- did not write. A guard that has never been seen to refuse is decoration. This plants one
-- real-looking row — a customer with an ordinary gen_random_uuid() id — runs the teardown's own
-- assertion against it, and expects the exception. Then rolls everything back.
--
-- Both directions: it also confirms the assertion PASSES on the clean database it starts from,
-- because a check that refuses everything would look identical to one that works.
begin;

do $control$
declare t text; n bigint; bad text := '';
begin
  -- CONTROL: on a clean database the assertion must pass, or the refusal below means nothing.
  foreach t in array array['movement','ledger_entry','order_charge','order_line','rental_order',
                           'repair_job','product_image','unit','product','customer','vendor'] loop
    execute format('select count(*) from %I where id::text not like ''00000000-0000-4000-8000-%%''', t) into n;
    if n > 0 then bad := bad || t || ' '; end if;
  end loop;
  if bad <> '' then raise exception 'CONTROL FAILED: the clean database already has non-seed rows in [%] — this probe must start from a clean or all-seed database', bad; end if;
  raise notice 'control ok: clean database passes the assertion';
end $control$;

-- Plant one real-looking row.
insert into customer (name, type, whatsapp, city) values ('Probe Real Customer', 'individual', '1000000099', 'Ahmedabad');

do $probe$
declare t text; n bigint; bad text := ''; refused boolean := false;
begin
  begin
    -- the teardown's assertion, verbatim
    foreach t in array array['movement','ledger_entry','order_charge','order_line','rental_order',
                             'repair_job','product_image','unit','product','customer','vendor'] loop
      execute format('select count(*) from %I where id::text not like ''00000000-0000-4000-8000-%%''', t) into n;
      if n > 0 then bad := bad || format('  %s: %s row(s) that are NOT seed%s', t, n, E'\n'); end if;
    end loop;
    if bad <> '' then
      raise exception E'dev_teardown refused — this database holds rows that dev_seed.sql did not write:\n%', bad;
    end if;
  exception when others then
    refused := true;
    raise notice 'REFUSAL FIRED as expected: %', split_part(sqlerrm, E'\n', 1);
  end;
  if not refused then
    raise exception 'PROBE FAILED: a real-looking customer row did NOT trigger the refusal — the teardown would have truncated it';
  end if;
  raise notice 'dev_teardown probe ok: refuses a non-seed row, passes a clean database';
end $probe$;

rollback;
