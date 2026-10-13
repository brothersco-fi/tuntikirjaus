-- =====================================================================
--  Tuntikirjaus – Brothers & Co.
--  Aja tämä Supabasen SQL Editorissa (koko tiedosto kerralla).
--  Tiedoston voi ajaa uudelleen myöhemmin: se päivittää olemassa olevan tietokannan.
--
--  Turvallisuusmalli:
--   * Tekijät eivät kirjaudu. Jokaisella on oma salainen linkki (avain),
--     ja he voivat vain katsoa oman tilansa, aloittaa kirjauksen (työmaa tai
--     siirtymä), lopettaa sen, perua siirtymän, merkitä muuta työtä, lisätä
--     unohtuneen kirjauksen, korjata omia kirjauksiaan viikon ajalta ja ladata
--     oman yhteenvedon (tekija_tila, aloita, saavu, lahde, peru_siirtyma,
--     lisaa_muu, lisaa_jalkikateen, korjaa_kirjaus, tekija_raportti).
--     Tekijän korjauksista jää alkuperäiset ajat talteen (alkup_saapui, alkup_lahti).
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
  tyomaa_id       bigint references public.tyomaat(id) on delete restrict,   -- pakollinen vain työmaakirjauksille
  tyyppi          text not null default 'tyomaa',   -- tyomaa | siirtyma | muu
  kuvaus          text,                              -- muun työn kuvaus
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

-- Päivitys 2 (siirtymät ja muu työ): turvallinen ajaa myös olemassa olevaan tietokantaan
alter table public.kirjaukset add column if not exists tyyppi text not null default 'tyomaa';
alter table public.kirjaukset add column if not exists kuvaus text;
-- Päivitys 3 (tekijän korjaukset): alkuperäiset ajat talteen, kun tekijä korjaa kirjausta
alter table public.kirjaukset add column if not exists alkup_saapui timestamptz;
alter table public.kirjaukset add column if not exists alkup_lahti  timestamptz;
alter table public.kirjaukset add column if not exists korjattu     timestamptz;
alter table public.kirjaukset alter column tyomaa_id drop not null;
alter table public.kirjaukset drop constraint if exists kirjaukset_tyyppi_check;
alter table public.kirjaukset add constraint kirjaukset_tyyppi_check check (tyyppi in ('tyomaa', 'siirtyma', 'muu'));
alter table public.kirjaukset drop constraint if exists kirjaukset_tyomaa_pakollinen;
alter table public.kirjaukset add constraint kirjaukset_tyomaa_pakollinen check (tyyppi <> 'tyomaa' or tyomaa_id is not null);
alter table public.kirjaukset drop constraint if exists kirjaukset_kuvaus_pakollinen;
alter table public.kirjaukset add constraint kirjaukset_kuvaus_pakollinen check (tyyppi <> 'muu' or length(trim(coalesce(kuvaus, ''))) > 0);

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
      select json_build_object('id', k.id, 'tyyppi', k.tyyppi, 'tyomaa_id', k.tyomaa_id, 'tyomaa', w.nimi,
                               'kuvaus', k.kuvaus, 'saapui', k.saapui)
      from public.kirjaukset k left join public.tyomaat w on w.id = k.tyomaa_id
      where k.tekija_id = t.id and k.lahti is null
      limit 1),
    'viimeiset', coalesce((
      select json_agg(x order by x.saapui desc) from (
        select k.id, k.saapui, k.lahti, k.tyyppi, k.kuvaus, k.kommentti, k.tyomaa_id, w.nimi as tyomaa
        from public.kirjaukset k left join public.tyomaat w on w.id = k.tyomaa_id
        where k.tekija_id = t.id and k.lahti is not null
          and k.saapui > now() - interval '21 days'
        order by k.saapui desc limit 60) x), '[]'::json)
  );
end $$;

-- Sisäinen apufunktio: estää päällekkäiset työmaa-/siirtymäkirjaukset (muu työ ei ole kellonaikasidottu)
create or replace function public.tarkista_paallekkain(p_tekija bigint, p_alku timestamptz, p_loppu timestamptz, p_ohita bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v public.kirjaukset;
begin
  select * into v from public.kirjaukset k
  where k.tekija_id = p_tekija and k.tyyppi <> 'muu' and k.id is distinct from p_ohita
    and k.saapui < p_loppu and coalesce(k.lahti, now()) > p_alku
  order by k.saapui limit 1;
  if found then
    raise exception 'Aika menee päällekkäin toisen kirjauksen kanssa (% – %).',
      to_char(v.saapui at time zone 'Europe/Helsinki', 'DD.MM. HH24.MI'),
      coalesce(to_char(v.lahti at time zone 'Europe/Helsinki', 'HH24.MI'), 'käynnissä');
  end if;
end $$;

drop function if exists public.aloita(text, text, bigint, text, double precision, double precision, real, text);

-- Aloittaa uuden kirjauksen: työmaa tai siirtymä.
-- Jos edellinen kirjaus on auki, se päättyy samalla hetkellä (kommentti tallentuu siihen).
-- Avoin siirtymä saa kohteekseen työmaan, jolle tekijä saapuu.
-- (Muu työ kirjataan kestona funktiolla lisaa_muu, ei aloitus/lopetus-periaatteella.)
create or replace function public.aloita(
  p_avain     text,
  p_tyyppi    text,
  p_tyomaa_id bigint default null,
  p_kuvaus    text default null,             -- ei käytössä (yhteensopivuus)
  p_lat       double precision default null,
  p_lon       double precision default null,
  p_tarkkuus  real default null,
  p_kommentti text default null,
  p_alkoi     timestamptz default null)        -- jos tekijä unohti painaa saapuessa
returns json language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tekija bigint;
  v_avoin  public.kirjaukset;
  v_tyomaa bigint := p_tyomaa_id;
  v_alku   timestamptz := now();
  v_avoin_id bigint;
begin
  select id into v_tekija from public.tekijat where avain = p_avain and aktiivinen;
  if v_tekija is null then
    raise exception 'Linkki ei ole voimassa. Pyydä uusi linkki työnjohdolta.';
  end if;
  if p_tyyppi not in ('tyomaa', 'siirtyma') then
    raise exception 'Tuntematon kirjauksen tyyppi.';
  end if;
  if p_tyyppi = 'tyomaa' and v_tyomaa is null then
    raise exception 'Valitse työmaa.';
  end if;
  if p_tyyppi = 'siirtyma' then
    v_tyomaa := null;
  end if;
  if v_tyomaa is not null then
    perform 1 from public.tyomaat where id = v_tyomaa and aktiivinen;
    if not found then
      raise exception 'Työmaata ei löytynyt. Päivitä sivu ja valitse uudelleen.';
    end if;
  end if;
  if p_alkoi is not null then
    if p_alkoi > now() + interval '2 minutes' then
      raise exception 'Saapumisaika ei voi olla tulevaisuudessa.';
    end if;
    if p_alkoi < now() - interval '14 hours' then
      raise exception 'Saapumisaika voi olla enintään 14 tuntia sitten. Lisää vanhempi kirjaus kohdasta "Unohtuiko kirjaus?".';
    end if;
    v_alku := least(p_alkoi, now());
  end if;

  select * into v_avoin from public.kirjaukset
  where tekija_id = v_tekija and lahti is null for update;
  if found then
    v_avoin_id := v_avoin.id;
    -- Tuplapainallus: sama asia on jo käynnissä
    if v_avoin.tyyppi = p_tyyppi and v_avoin.tyomaa_id is not distinct from v_tyomaa then
      return public.tekija_tila(p_avain);
    end if;
    if v_avoin.saapui < now() - interval '14 hours' then
      raise exception 'Edellinen kirjaus on vielä auki. Kirjaa ensin, mihin aikaan lopetit.';
    end if;
    if v_alku < v_avoin.saapui then
      raise exception 'Saapumisaika on ennen käynnissä olevan kirjauksen alkua.';
    end if;
    update public.kirjaukset set
      lahti          = v_alku,
      lahti_lat      = p_lat,
      lahti_lon      = p_lon,
      lahti_tarkkuus = p_tarkkuus,
      kommentti      = coalesce(nullif(left(trim(coalesce(p_kommentti, '')), 1000), ''), kommentti),
      tyomaa_id      = case when tyyppi = 'siirtyma' and tyomaa_id is null then v_tyomaa else tyomaa_id end
    where id = v_avoin.id;
  end if;

  if p_alkoi is not null then
    perform public.tarkista_paallekkain(v_tekija, v_alku, now(), null);
  end if;

  begin
    insert into public.kirjaukset (tekija_id, tyomaa_id, tyyppi, kuvaus, saapui, saapui_lat, saapui_lon, saapui_tarkkuus, huomio)
    values (v_tekija, v_tyomaa, p_tyyppi, null, v_alku, p_lat, p_lon, p_tarkkuus,
            case when p_alkoi is not null then 'Saapumisaika merkitty jälkikäteen' end);
  exception when unique_violation then
    null;                                          -- samanaikainen tuplapainallus
  end;

  return public.tekija_tila(p_avain);
end $$;

-- Vanha nimi työmaalle saapumiselle (pidetään yhteensopivuuden vuoksi)
create or replace function public.saavu(
  p_avain     text,
  p_tyomaa_id bigint,
  p_lat       double precision default null,
  p_lon       double precision default null,
  p_tarkkuus  real default null)
returns json language plpgsql security definer set search_path = public, pg_temp as $$
begin
  return public.aloita(p_avain, 'tyomaa', p_tyomaa_id, null, p_lat, p_lon, p_tarkkuus, null, null);
end $$;

-- Muu työ (esim. tarvikehaku, varastolla): tekijä merkitsee itse päivän, keston ja kuvauksen.
create or replace function public.lisaa_muu(
  p_avain     text,
  p_paiva     date,
  p_kesto_min integer,
  p_kuvaus    text,
  p_tyomaa_id bigint default null)
returns json language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tekija bigint;
  v_kuvaus text := nullif(left(trim(coalesce(p_kuvaus, '')), 200), '');
  v_tanaan date := (now() at time zone 'Europe/Helsinki')::date;
  v_loppu  timestamptz;
begin
  select id into v_tekija from public.tekijat where avain = p_avain and aktiivinen;
  if v_tekija is null then
    raise exception 'Linkki ei ole voimassa. Pyydä uusi linkki työnjohdolta.';
  end if;
  if v_kuvaus is null then
    raise exception 'Kirjoita lyhyesti, mitä teit.';
  end if;
  if p_kesto_min is null or p_kesto_min < 5 or p_kesto_min > 720 then
    raise exception 'Valitse kesto (enintään 12 tuntia).';
  end if;
  if p_paiva is null or p_paiva > v_tanaan or p_paiva < v_tanaan - 31 then
    raise exception 'Päivän pitää olla viimeisen kuukauden ajalta, ei tulevaisuudessa.';
  end if;
  if p_tyomaa_id is not null then
    perform 1 from public.tyomaat where id = p_tyomaa_id and aktiivinen;
    if not found then
      raise exception 'Työmaata ei löytynyt. Päivitä sivu ja valitse uudelleen.';
    end if;
  end if;

  -- Tänään merkitty työ päättyy merkintähetkeen, aiempi päivä klo 16.00
  v_loppu := case when p_paiva = v_tanaan then now()
                  else (p_paiva + time '16:00') at time zone 'Europe/Helsinki' end;

  insert into public.kirjaukset (tekija_id, tyomaa_id, tyyppi, kuvaus, saapui, lahti)
  values (v_tekija, p_tyomaa_id, 'muu', v_kuvaus, v_loppu - make_interval(mins => p_kesto_min), v_loppu);

  return public.tekija_tila(p_avain);
end $$;

-- Unohtunut kirjaus: tekijä lisää työmaakäynnin jälkikäteen (enintään viikon takaa)
create or replace function public.lisaa_jalkikateen(
  p_avain     text,
  p_tyomaa_id bigint,
  p_alkoi     timestamptz,
  p_paattyi   timestamptz,
  p_kommentti text default null)
returns json language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tekija bigint;
begin
  select id into v_tekija from public.tekijat where avain = p_avain and aktiivinen;
  if v_tekija is null then
    raise exception 'Linkki ei ole voimassa. Pyydä uusi linkki työnjohdolta.';
  end if;
  perform 1 from public.tyomaat where id = p_tyomaa_id and aktiivinen;
  if not found then
    raise exception 'Valitse työmaa.';
  end if;
  if p_alkoi is null or p_paattyi is null or p_paattyi <= p_alkoi then
    raise exception 'Tarkista ajat: lopetuksen pitää olla aloituksen jälkeen.';
  end if;
  if p_paattyi > now() + interval '2 minutes' then
    raise exception 'Kirjaus ei voi päättyä tulevaisuudessa.';
  end if;
  if p_alkoi < now() - interval '8 days' then
    raise exception 'Yli viikon vanhoja kirjauksia voi lisätä vain työnjohto.';
  end if;
  if p_paattyi - p_alkoi > interval '16 hours' then
    raise exception 'Yksi kirjaus voi olla enintään 16 tuntia.';
  end if;
  perform public.tarkista_paallekkain(v_tekija, p_alkoi, p_paattyi, null);

  insert into public.kirjaukset (tekija_id, tyomaa_id, tyyppi, saapui, lahti, kommentti, huomio)
  values (v_tekija, p_tyomaa_id, 'tyomaa', p_alkoi, least(p_paattyi, now()),
          nullif(left(trim(coalesce(p_kommentti, '')), 1000), ''), 'Tekijä lisännyt jälkikäteen');
  return public.tekija_tila(p_avain);
end $$;

-- Tekijä korjaa omaa kirjaustaan (viimeisen viikon ajalta). Alkuperäiset ajat jäävät talteen.
create or replace function public.korjaa_kirjaus(
  p_avain     text,
  p_id        bigint,
  p_tyomaa_id bigint default null,
  p_alkoi     timestamptz default null,
  p_paattyi   timestamptz default null,
  p_kommentti text default null,
  p_kuvaus    text default null,
  p_kesto_min integer default null)
returns json language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tekija bigint;
  v       public.kirjaukset;
  v_kuvaus text := nullif(left(trim(coalesce(p_kuvaus, '')), 200), '');
  v_alkup  text;
begin
  select id into v_tekija from public.tekijat where avain = p_avain and aktiivinen;
  if v_tekija is null then
    raise exception 'Linkki ei ole voimassa. Pyydä uusi linkki työnjohdolta.';
  end if;
  select * into v from public.kirjaukset where id = p_id and tekija_id = v_tekija for update;
  if not found then
    raise exception 'Kirjausta ei löytynyt.';
  end if;
  if v.lahti is null then
    raise exception 'Käynnissä olevaa kirjausta ei voi korjata. Lopeta se ensin.';
  end if;
  if v.saapui < now() - interval '8 days' then
    raise exception 'Yli viikon vanhoja kirjauksia voi korjata vain työnjohto.';
  end if;
  if p_tyomaa_id is not null and p_tyomaa_id is distinct from v.tyomaa_id then
    perform 1 from public.tyomaat where id = p_tyomaa_id and aktiivinen;
    if not found then
      raise exception 'Työmaata ei löytynyt.';
    end if;
  end if;

  v_alkup := case when v.alkup_saapui is null then
    'Tekijä korjannut (alkup. ' ||
    case when v.tyyppi = 'muu'
      then replace(trim_scale(round(extract(epoch from v.lahti - v.saapui) / 3600.0, 2))::text, '.', ',') || ' h'
      else to_char(v.saapui at time zone 'Europe/Helsinki', 'DD.MM. HH24.MI') || '–' ||
           to_char(v.lahti at time zone 'Europe/Helsinki', 'HH24.MI') end || ')'
  end;

  if v.tyyppi = 'muu' then
    if v_kuvaus is null then
      raise exception 'Kirjoita lyhyesti, mitä teit.';
    end if;
    if p_kesto_min is null or p_kesto_min < 5 or p_kesto_min > 720 then
      raise exception 'Valitse kesto (enintään 12 tuntia).';
    end if;
    update public.kirjaukset set
      kuvaus       = v_kuvaus,
      tyomaa_id    = p_tyomaa_id,
      saapui       = lahti - make_interval(mins => p_kesto_min),
      alkup_saapui = coalesce(alkup_saapui, saapui),
      alkup_lahti  = coalesce(alkup_lahti, lahti),
      korjattu     = now(),
      huomio       = nullif(concat_ws('; ', huomio, v_alkup), '')
    where id = v.id;
  else
    if v.tyyppi = 'tyomaa' and p_tyomaa_id is null then
      raise exception 'Valitse työmaa.';
    end if;
    if p_alkoi is null or p_paattyi is null or p_paattyi <= p_alkoi then
      raise exception 'Tarkista ajat: lopetuksen pitää olla aloituksen jälkeen.';
    end if;
    if p_paattyi > now() + interval '2 minutes' then
      raise exception 'Kirjaus ei voi päättyä tulevaisuudessa.';
    end if;
    if p_alkoi < now() - interval '8 days' then
      raise exception 'Yli viikon vanhoja aikoja voi korjata vain työnjohto.';
    end if;
    if p_paattyi - p_alkoi > interval '16 hours' then
      raise exception 'Yksi kirjaus voi olla enintään 16 tuntia.';
    end if;
    perform public.tarkista_paallekkain(v_tekija, p_alkoi, p_paattyi, v.id);
    update public.kirjaukset set
      tyomaa_id    = p_tyomaa_id,
      saapui       = p_alkoi,
      lahti        = least(p_paattyi, now()),
      kommentti    = nullif(left(trim(coalesce(p_kommentti, '')), 1000), ''),
      alkup_saapui = coalesce(alkup_saapui, saapui),
      alkup_lahti  = coalesce(alkup_lahti, lahti),
      korjattu     = now(),
      huomio       = nullif(concat_ws('; ', huomio, v_alkup), '')
    where id = v.id;
  end if;
  return public.tekija_tila(p_avain);
end $$;

-- Tekijän oma yhteenveto laskutusta varten (vain omat kirjaukset)
create or replace function public.tekija_raportti(p_avain text, p_alku date, p_loppu date)
returns json language plpgsql security definer set search_path = public, pg_temp as $$
declare
  t public.tekijat;
begin
  select * into t from public.tekijat where avain = p_avain and aktiivinen;
  if not found then
    raise exception 'Linkki ei ole voimassa. Pyydä uusi linkki työnjohdolta.';
  end if;
  if p_alku is null or p_loppu is null or p_loppu < p_alku or p_loppu - p_alku > 370 then
    raise exception 'Tarkista aikaväli (enintään vuosi).';
  end if;
  return json_build_object(
    'nimi', t.nimi, 'yritys', t.yritys, 'tuntihinta', t.tuntihinta,
    'kirjaukset', coalesce((
      select json_agg(x order by x.saapui) from (
        select k.saapui, k.lahti, k.tyyppi, k.kuvaus, k.kommentti, w.nimi as tyomaa
        from public.kirjaukset k left join public.tyomaat w on w.id = k.tyomaa_id
        where k.tekija_id = t.id and k.lahti is not null
          and k.saapui >= (p_alku::timestamp at time zone 'Europe/Helsinki')
          and k.saapui <  ((p_loppu + 1)::timestamp at time zone 'Europe/Helsinki')) x), '[]'::json)
  );
end $$;

-- Peruu käynnissä olevan siirtymän (esim. tekijä ei mennytkään toiselle työmaalle)
create or replace function public.peru_siirtyma(p_avain text)
returns json language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tekija bigint;
begin
  select id into v_tekija from public.tekijat where avain = p_avain and aktiivinen;
  if v_tekija is null then
    raise exception 'Linkki ei ole voimassa. Pyydä uusi linkki työnjohdolta.';
  end if;
  delete from public.kirjaukset where tekija_id = v_tekija and lahti is null and tyyppi = 'siirtyma';
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
revoke execute on function public.aloita(text, text, bigint, text, double precision, double precision, real, text, timestamptz) from public;
revoke execute on function public.tarkista_paallekkain(bigint, timestamptz, timestamptz, bigint) from public, anon, authenticated;
revoke execute on function public.lisaa_jalkikateen(text, bigint, timestamptz, timestamptz, text) from public;
revoke execute on function public.korjaa_kirjaus(text, bigint, bigint, timestamptz, timestamptz, text, text, integer) from public;
revoke execute on function public.tekija_raportti(text, date, date) from public;
revoke execute on function public.peru_siirtyma(text) from public;
revoke execute on function public.lisaa_muu(text, date, integer, text, bigint) from public;
revoke execute on function public.uusi_linkki(bigint) from public, anon;
grant  execute on function public.tekija_tila(text) to anon, authenticated;
grant  execute on function public.saavu(text, bigint, double precision, double precision, real) to anon, authenticated;
grant  execute on function public.lahde(text, text, double precision, double precision, real, timestamptz) to anon, authenticated;
grant  execute on function public.aloita(text, text, bigint, text, double precision, double precision, real, text, timestamptz) to anon, authenticated;
grant  execute on function public.lisaa_jalkikateen(text, bigint, timestamptz, timestamptz, text) to anon, authenticated;
grant  execute on function public.korjaa_kirjaus(text, bigint, bigint, timestamptz, timestamptz, text, text, integer) to anon, authenticated;
grant  execute on function public.tekija_raportti(text, date, date) to anon, authenticated;
grant  execute on function public.peru_siirtyma(text) to anon, authenticated;
grant  execute on function public.lisaa_muu(text, date, integer, text, bigint) to anon, authenticated;
grant  execute on function public.uusi_linkki(bigint) to authenticated;
grant  execute on function public.on_admin() to anon, authenticated;
