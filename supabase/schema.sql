-- =====================================================================
--  Tuntikirjaus – Brothers & Co.
--  Aja tämä kerran Supabasen SQL Editorissa (koko tiedosto kerralla).
--
--  Turvallisuusmalli:
--   * Tekijät eivät kirjaudu. Jokaisella on oma salainen linkki (avain),
--     ja he voivat tehdä vain kolme asiaa: katsoa oman tilansa, kirjautua
--     työmaalle ja lähteä työmaalta (funktiot tekija_tila, saavu, lahde).
--   * Taulut ovat lukittuja (RLS). Vain adminit-tauluun lisätyt käyttäjät
--     näkevät ja muokkaavat tietoja hallintasivulla.
-- =====================================================================

-- ---------- Apufunktio: satunnainen 22 merkin avain linkkiin ----------
create or replace function public.uusi_avain()
returns text language sql volatile as $$
  select translate(encode(uuid_send(gen_random_uuid()), 'base64'), '+/=', '-_')
$$;

-- ---------- Taulut ----------
create table if not exists public.tyomaat (
  id            bigint generated always as identity primary key,
  nimi          text not null check (length(trim(nimi)) > 0),
  osoite        text,
  asiakas       text,
  lat           double precision,
  lon           double precision,
  sade_m        integer not null default 300 check (sade_m between 50 and 5000),
  laskutushinta numeric(10,2),          -- €/h asiakkaalle (valinnainen)
  aktiivinen    boolean not null default true,
  luotu         timestamptz not null default now()
);

create table if not exists public.tekijat (
  id          bigint generated always as identity primary key,
  nimi        text not null check (length(trim(nimi)) > 0),
  yritys      text,                     -- alihankkijan yritys
  puhelin     text,
  tuntihinta  numeric(10,2),            -- €/h, mitä tekijälle maksetaan
  avain       text not null unique default public.uusi_avain(),
  aktiivinen  boolean not null default true,
  luotu       timestamptz not null default now()
);

create table if not exists public.kirjaukset (
  id              bigint generated always as identity primary key,
  tekija_id       bigint not null references public.tekijat(id) on delete restrict,
  tyomaa_id       bigint not null references public.tyomaat(id) on delete restrict,
  saapui          timestamptz not null default now(),
  lahti           timestamptz,
  saapui_lat      double precision,
  saapui_lon      double precision,
  saapui_tarkkuus real,
  lahti_lat       double precision,
  lahti_lon       double precision,
  lahti_tarkkuus  real,
  kommentti       text,
  huomio          text,                 -- esim. "Lähtöaika syötetty käsin"
  luotu           timestamptz not null default now(),
  constraint lahti_saapumisen_jalkeen check (lahti is null or lahti >= saapui)
);

create index if not exists kirjaukset_saapui_idx on public.kirjaukset (saapui);
-- Tekijällä voi olla vain yksi avoin kirjaus kerrallaan
create unique index if not exists kirjaukset_yksi_avoin on public.kirjaukset (tekija_id) where lahti is null;

create table if not exists public.adminit (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  lisatty  timestamptz not null default now()
);

-- ---------- Kuka on admin ----------
create or replace function public.on_admin()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.adminit where user_id = auth.uid())
$$;

-- ---------- Rivitason suojaus ----------
alter table public.tyomaat    enable row level security;
alter table public.tekijat    enable row level security;
alter table public.kirjaukset enable row level security;
alter table public.adminit    enable row level security;

drop policy if exists admin_kaikki on public.tyomaat;
drop policy if exists admin_kaikki on public.tekijat;
drop policy if exists admin_kaikki on public.kirjaukset;
drop policy if exists oma_rivi     on public.adminit;

create policy admin_kaikki on public.tyomaat    for all to authenticated using (public.on_admin()) with check (public.on_admin());
create policy admin_kaikki on public.tekijat    for all to authenticated using (public.on_admin()) with check (public.on_admin());
create policy admin_kaikki on public.kirjaukset for all to authenticated using (public.on_admin()) with check (public.on_admin());
create policy oma_rivi     on public.adminit    for select to authenticated using (user_id = auth.uid());

revoke all on public.tyomaat, public.tekijat, public.kirjaukset, public.adminit from anon;
grant select, insert, update, delete on public.tyomaat, public.tekijat, public.kirjaukset to authenticated;
grant select on public.adminit to authenticated;

-- =====================================================================
--  Tekijän toiminnot (toimivat ilman kirjautumista, avaimella)
-- =====================================================================

create or replace function public.tekija_tila(p_avain text)
returns json language plpgsql security definer set search_path = public, pg_temp as $$
declare
  t public.tekijat;
begin
  select * into t from public.tekijat where avain = p_avain and aktiivinen;
  if not found then
    raise exception 'Linkki ei ole voimassa. Pyydä uusi linkki työnjohdolta.';
  end if;

  return json_build_object(
    'nimi', t.nimi,
    'tyomaat', coalesce((
      select json_agg(json_build_object(
               'id', w.id, 'nimi', w.nimi, 'osoite', w.osoite,
               'lat', w.lat, 'lon', w.lon, 'sade_m', w.sade_m) order by w.nimi)
      from public.tyomaat w where w.aktiivinen), '[]'::json),
    'avoin', (
      select json_build_object('id', k.id, 'tyomaa_id', k.tyomaa_id, 'tyomaa', w.nimi, 'saapui', k.saapui)
      from public.kirjaukset k join public.tyomaat w on w.id = k.tyomaa_id
      where k.tekija_id = t.id and k.lahti is null
      limit 1),
    'viimeiset', coalesce((
      select json_agg(x order by x.saapui desc) from (
        select k.saapui, k.lahti, w.nimi as tyomaa
        from public.kirjaukset k join public.tyomaat w on w.id = k.tyomaa_id
        where k.tekija_id = t.id and k.lahti is not null
          and k.saapui > now() - interval '21 days'
        order by k.saapui desc limit 40) x), '[]'::json)
  );
end $$;

create or replace function public.saavu(
  p_avain     text,
  p_tyomaa_id bigint,
  p_lat       double precision default null,
  p_lon       double precision default null,
  p_tarkkuus  real default null)
returns json language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tekija bigint;
  v_avoin  public.kirjaukset;
begin
  select id into v_tekija from public.tekijat where avain = p_avain and aktiivinen;
  if v_tekija is null then
    raise exception 'Linkki ei ole voimassa. Pyydä uusi linkki työnjohdolta.';
  end if;

  perform 1 from public.tyomaat where id = p_tyomaa_id and aktiivinen;
  if not found then
    raise exception 'Työmaata ei löytynyt. Päivitä sivu ja valitse uudelleen.';
  end if;

  select * into v_avoin from public.kirjaukset where tekija_id = v_tekija and lahti is null;
  if found then
    if v_avoin.tyomaa_id = p_tyomaa_id then
      return public.tekija_tila(p_avain);         -- tuplapainallus, ei tehdä mitään
    end if;
    raise exception 'Olet vielä kirjautuneena toisella työmaalla. Paina ensin Lähdin.';
  end if;

  begin
    insert into public.kirjaukset (tekija_id, tyomaa_id, saapui_lat, saapui_lon, saapui_tarkkuus)
    values (v_tekija, p_tyomaa_id, p_lat, p_lon, p_tarkkuus);
  exception when unique_violation then
    null;                                          -- samanaikainen tuplapainallus
  end;

  return public.tekija_tila(p_avain);
end $$;

create or replace function public.lahde(
  p_avain     text,
  p_kommentti text default null,
  p_lat       double precision default null,
  p_lon       double precision default null,
  p_tarkkuus  real default null,
  p_lahti     timestamptz default null)          -- vain jos lähtö unohtui
returns json language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tekija bigint;
  v_avoin  public.kirjaukset;
  v_aika   timestamptz := now();
  v_kasin  boolean := p_lahti is not null;
begin
  select id into v_tekija from public.tekijat where avain = p_avain and aktiivinen;
  if v_tekija is null then
    raise exception 'Linkki ei ole voimassa. Pyydä uusi linkki työnjohdolta.';
  end if;

  select * into v_avoin from public.kirjaukset
  where tekija_id = v_tekija and lahti is null for update;
  if not found then
    raise exception 'Sinulla ei ole avointa kirjausta.';
  end if;

  if v_kasin then
    if p_lahti < v_avoin.saapui or p_lahti > now() + interval '5 minutes' then
      raise exception 'Lähtöaika ei voi olla ennen saapumista eikä tulevaisuudessa.';
    end if;
    v_aika := least(p_lahti, now());
  end if;

  update public.kirjaukset set
    lahti          = v_aika,
    lahti_lat      = case when v_kasin then null else p_lat end,
    lahti_lon      = case when v_kasin then null else p_lon end,
    lahti_tarkkuus = case when v_kasin then null else p_tarkkuus end,
    kommentti      = nullif(left(trim(coalesce(p_kommentti, '')), 1000), ''),
    huomio         = nullif(concat_ws('; ', huomio,
                       case when v_kasin then 'Lähtöaika syötetty jälkikäteen' end), '')
  where id = v_avoin.id;

  return public.tekija_tila(p_avain);
end $$;

-- Uusi linkki tekijälle (vanha lakkaa toimimasta). Toimii vain adminille (RLS).
create or replace function public.uusi_linkki(p_tekija_id bigint)
returns text language sql security invoker set search_path = public, pg_temp as $$
  update public.tekijat set avain = public.uusi_avain() where id = p_tekija_id returning avain
$$;

revoke execute on function public.tekija_tila(text) from public;
revoke execute on function public.saavu(text, bigint, double precision, double precision, real) from public;
revoke execute on function public.lahde(text, text, double precision, double precision, real, timestamptz) from public;
revoke execute on function public.uusi_linkki(bigint) from public, anon;
grant  execute on function public.tekija_tila(text) to anon, authenticated;
grant  execute on function public.saavu(text, bigint, double precision, double precision, real) to anon, authenticated;
grant  execute on function public.lahde(text, text, double precision, double precision, real, timestamptz) to anon, authenticated;
grant  execute on function public.uusi_linkki(bigint) to authenticated;
grant  execute on function public.on_admin() to anon, authenticated;
