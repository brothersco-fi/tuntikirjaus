# Tuntikirjaus – Brothers & Co.

Työmaan tuntikirjaus puhelimella. Tekijät eivät tarvitse tunnuksia: jokainen saa oman linkin, avaa sen puhelimella ja painaa **Saavuin** / **Lähdin**. Kellonaika ja puhelimen sijainti tallentuvat.

- `index.html` – tekijän kirjaussivu (kirjautuminen puhelinnumerolla ja salasanalla)
- `hallinta.html` – hallinta: kuka on nyt työmaalla, kirjaukset, korjaukset, yhteenvedot, Excel, työmaat, tekijät ja kuvat
- `asiakas.html` – asiakkaan katselusivu työmaan kuville (vain hallinnassa valitut kuvat)
- `raportti.js` – kuvaraportin PDF
- `supabase/schema.sql` – tietokanta (aja kerran Supabasessa)
- `config.js` – Supabase-osoite ja julkinen avain

## Käyttöönotto

1. **Supabase**: luo projekti (alue: Stockholm). Avaa *SQL Editor*, liitä `supabase/schema.sql` ja paina *Run*. Saman tiedoston voi ajaa uudelleen päivitysten jälkeen.
2. **Oma tunnus hallintaan**: *Authentication → Users → Add user* (sähköposti + salasana, "Auto confirm"). Aja sitten SQL Editorissa:
   ```sql
   insert into public.adminit (user_id)
   select id from auth.users where email = 'andy@brothersco.fi';
   ```
3. **Sulje vapaa rekisteröityminen**: *Authentication → Sign In / Providers* → poista "Allow new users to sign up".
4. **config.js**: kopioi *Project URL* ja *publishable key* (Project Settings → API Keys). Älä koskaan käytä secret- tai service_role-avainta.
5. **GitHub Pages**: tiedostot julkiseen repoon, *Settings → Pages → Deploy from branch: main / root*.

## Tekijän kirjautuminen

1. Lisää tekijä hallinnassa ja lähetä hänelle **kutsulinkki** (Tekstiviesti-nappi).
2. Tekijä avaa linkin ja **luo salasanan**. Tunnuksena on hänen puhelinnumeronsa.
3. Sen jälkeen kutsulinkki lakkaa toimimasta, ja tekijä kirjautuu osoitteessa `brothersco-fi.github.io/tuntikirjaus` puhelinnumerolla ja salasanalla. Kirjautuminen säilyy puhelimessa, kunnes hän kirjautuu ulos.
4. Jos salasana unohtuu, paina tekijän kohdalla **Nollaa salasana** ja lähetä uusi kutsulinkki. Viiden väärän yrityksen jälkeen tunnus lukittuu 15 minuutiksi.

## Tekijän toiminnot

- **Saavuin / Lähdin** työmaalla. Jos painallus unohtui saapuessa, *Unohdin painaa saapuessa* -kohdasta voi valita saapumisajan.
- **Siirryn toiselle työmaalle**: siirtymä lasketaan työajaksi ja kohdistuu työmaalle, jolle tekijä saapuu.
- **Matka-aika** (esim. varastolta työmaalle): päivä, kesto ja työmaa. Näkyy raporteissa omana sarakkeenaan asiakaslaskutusta varten. Myös työmaalta toiselle siirtymät lasketaan matka-aikaan.
- **Muu työ** (esim. tarvikehaku, varastolla): kuvaus, päivä ja kesto, ja halutessa työmaa.
- **Korjaa** omia kirjauksia ja **lisää unohtunut kirjaus** viikon ajalta. Korjaukset näkyvät hallinnassa, ja alkuperäiset ajat jäävät talteen.
- **Oma yhteenveto laskutusta varten**: tunnit valitulta ajalta ja Excel-tiedosto.
- **Kuvat**: työmaa, työvaihe omin sanoin (esim. "Purku", "Pohjalaasti"), halutessa kommentti ja kuvat. Aiemmat vaiheet tulevat ehdotuksiksi, jotta samat vaiheet pysyvät yhdessä. Kuvat pienennetään puhelimessa ennen lähetystä.

## Kuvadokumentointi

- Hallinnan **Kuvat**-välilehdellä näet työmaan kuvat työvaiheittain. Voit nimetä vaiheen uudelleen (esim. yhdistää kaksi eri tavalla kirjoitettua), poistaa kuvan ja ladata PDF-raportin.
- Merkitse **Asiakkaalle** ne kuvat, jotka asiakas saa nähdä. Paina **Luo asiakkaan linkki** ja lähetä linkki asiakkaalle. Asiakas näkee vain merkityt kuvat ja voi ladata niistä PDF:n.
- **Poista linkki** lopettaa asiakkaan pääsyn heti. Uusi linkki on eri osoite.
- Kuvat ovat yksityisessä tallennustilassa. Asiakkaalle merkityn kuvan osoite on voimassa viisi vuotta; jos merkintä poistetaan, kuva katoaa asiakkaan sivulta.

Kutsulinkki on muotoa `.../tuntikirjaus/?nimi=etunimi-sukunimi&k=...`. Nimi on vain tunnistamisen helpottamiseksi.

## Päivittäinen käyttö

1. Lisää hallinnassa työmaat (osoite → *Hae sijainti osoitteesta*) ja tekijät (nimi, puhelin, tuntihinta).
2. Lähetä tekijälle linkki *Tekstiviesti*-painikkeella. Tekijä lisää sivun puhelimen kotinäyttöön.
3. Hallinnan *Nyt*-välilehti näyttää, kuka on millä työmaalla. *Yhteenveto* ja *Lataa Excel* kuukauden lopussa laskutusta ja alihankintalaskujen tarkistusta varten.

Jos kutsulinkki joutuu vääriin käsiin ennen kuin tekijä on luonut salasanan, paina *Luo uusi linkki*: vanha lakkaa toimimasta heti.

Supabasen ilmainen paketti riittää. Se menee tauolle vain, jos viikkoon ei tule yhtään kirjausta; silloin projektin saa käyntiin Supabasen hallinnasta yhdellä painalluksella.
