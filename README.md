# Tuntikirjaus – Brothers & Co.

Työmaan tuntikirjaus puhelimella. Tekijät eivät tarvitse tunnuksia: jokainen saa oman linkin, avaa sen puhelimella ja painaa **Saavuin** / **Lähdin**. Kellonaika ja puhelimen sijainti tallentuvat.

- `index.html` – tekijän kirjaussivu (avataan omalla linkillä `?k=...`)
- `hallinta.html` – hallinta: kuka on nyt työmaalla, kirjaukset, korjaukset, yhteenvedot, Excel, työmaat ja tekijät
- `supabase/schema.sql` – tietokanta (aja kerran Supabasessa)
- `config.js` – Supabase-osoite ja julkinen avain

## Käyttöönotto

1. **Supabase**: luo projekti (alue: Stockholm). Avaa *SQL Editor*, liitä `supabase/schema.sql` ja paina *Run*.
2. **Oma tunnus hallintaan**: *Authentication → Users → Add user* (sähköposti + salasana, "Auto confirm"). Aja sitten SQL Editorissa:
   ```sql
   insert into public.adminit (user_id)
   select id from auth.users where email = 'andy@brothersco.fi';
   ```
3. **Sulje vapaa rekisteröityminen**: *Authentication → Sign In / Providers* → poista "Allow new users to sign up".
4. **config.js**: kopioi *Project URL* ja *publishable key* (Project Settings → API Keys). Älä koskaan käytä secret- tai service_role-avainta.
5. **GitHub Pages**: tiedostot julkiseen repoon, *Settings → Pages → Deploy from branch: main / root*.

## Päivittäinen käyttö

1. Lisää hallinnassa työmaat (osoite → *Hae sijainti osoitteesta*) ja tekijät (nimi, puhelin, tuntihinta).
2. Lähetä tekijälle linkki *Tekstiviesti*-painikkeella. Tekijä lisää sivun puhelimen kotinäyttöön.
3. Hallinnan *Nyt*-välilehti näyttää, kuka on millä työmaalla. *Yhteenveto* ja *Lataa Excel* kuukauden lopussa laskutusta ja alihankintalaskujen tarkistusta varten.

Jos linkki joutuu vääriin käsiin, paina tekijän kohdalla *Luo uusi linkki*: vanha lakkaa toimimasta heti.

Supabasen ilmainen paketti riittää. Se menee tauolle vain, jos viikkoon ei tule yhtään kirjausta; silloin projektin saa käyntiin Supabasen hallinnasta yhdellä painalluksella.
