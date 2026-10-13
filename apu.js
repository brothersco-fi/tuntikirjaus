// Yhteiset apufunktiot kirjaus- ja hallintasivulle
(function () {
  const cfg = window.TK_CONFIG || {};
  const TZ = 'Europe/Helsinki';

  const fAika = new Intl.DateTimeFormat('fi-FI', { hour: 'numeric', minute: '2-digit', timeZone: TZ });
  const fPaiva = new Intl.DateTimeFormat('fi-FI', { weekday: 'short', day: 'numeric', month: 'numeric', timeZone: TZ });
  const fPvm = new Intl.DateTimeFormat('fi-FI', { day: 'numeric', month: 'numeric', year: 'numeric', timeZone: TZ });
  const fPitka = new Intl.DateTimeFormat('fi-FI', { weekday: 'long', day: 'numeric', month: 'long', timeZone: TZ });
  const fNum = new Intl.NumberFormat('fi-FI', { maximumFractionDigits: 2 });
  const fNum1 = new Intl.NumberFormat('fi-FI', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  const fEur = new Intl.NumberFormat('fi-FI', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 });
  const fYmd = new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone: TZ });

  const TK = {
    cfg,
    konfiguroitu: () => !!cfg.supabaseUrl && !/YOUR-/.test(cfg.supabaseUrl + cfg.supabaseKey),
    client: () => window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey),

    aika: d => fAika.format(new Date(d)),
    paiva: d => fPaiva.format(new Date(d)),
    pvm: d => fPvm.format(new Date(d)),
    pitkaPaiva: d => fPitka.format(new Date(d)),
    ymd: d => fYmd.format(new Date(d)),              // 2026-10-13 Suomen ajassa
    num: n => fNum.format(n),
    num1: n => fNum1.format(n),
    eur: n => fEur.format(n),

    tunnit(saapui, lahti) {
      if (!lahti) return null;
      return Math.max(0, (new Date(lahti) - new Date(saapui)) / 3600000);
    },
    kesto(ms) {
      const min = Math.max(0, Math.floor(ms / 60000));
      const h = Math.floor(min / 60), m = min % 60;
      return h ? `${h} h ${m} min` : `${m} min`;
    },

    // Etäisyys metreinä kahden pisteen välillä
    etaisyys(lat1, lon1, lat2, lon2) {
      if ([lat1, lon1, lat2, lon2].some(v => v === null || v === undefined)) return null;
      const R = 6371000, r = Math.PI / 180;
      const dLat = (lat2 - lat1) * r, dLon = (lon2 - lon1) * r;
      const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin(dLon / 2) ** 2;
      return 2 * R * Math.asin(Math.sqrt(a));
    },
    matka(m) {
      if (m === null || m === undefined) return '';
      return m < 1000 ? `${Math.round(m / 10) * 10} m` : `${fNum1.format(m / 1000)} km`;
    },
    karttalinkki: (lat, lon) => `https://www.google.com/maps?q=${lat},${lon}`,

    // Hakee puhelimen sijainnin. Palauttaa {lat, lon, tarkkuus} tai {virhe: 'estetty' | 'ei_saatavilla' | 'aikakatkaisu' | 'ei_tukea'}.
    // Yrittää ensin tarkalla GPS:llä, sitten nopeammalla verkkosijainnilla (sisätiloissa GPS voi olla hidas).
    async sijainti(maxIka = 60000) {
      if (!('geolocation' in navigator)) return { virhe: 'ei_tukea' };
      const yritys = (tarkka, aika) => new Promise(res => {
        let valmis = false;
        const loppu = v => { if (!valmis) { valmis = true; clearTimeout(t); res(v); } };
        const t = setTimeout(() => loppu({ virhe: 'aikakatkaisu' }), aika + 1500);
        navigator.geolocation.getCurrentPosition(
          p => loppu({ lat: p.coords.latitude, lon: p.coords.longitude, tarkkuus: Math.round(p.coords.accuracy) }),
          e => loppu({ virhe: e.code === 1 ? 'estetty' : e.code === 3 ? 'aikakatkaisu' : 'ei_saatavilla' }),
          { enableHighAccuracy: tarkka, maximumAge: maxIka, timeout: aika }
        );
      });
      let r = await yritys(true, 10000);
      if (r.virhe && r.virhe !== 'estetty') r = await yritys(false, 8000);
      return r;
    },

    virhe(e) {
      const v = (e && (e.message || e.error_description)) || String(e || '');
      if (/Failed to fetch|NetworkError|Load failed/i.test(v)) return 'Ei yhteyttä. Tarkista nettiyhteys ja yritä uudelleen.';
      return v || 'Jokin meni vikaan. Yritä uudelleen.';
    },

    esc(s) {
      return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    },

    toast(teksti, tyyppi = 'ok') {
      let el = document.getElementById('toast');
      if (!el) { el = document.createElement('div'); el.id = 'toast'; el.setAttribute('role', 'status'); document.body.appendChild(el); }
      el.textContent = teksti;
      el.dataset.tyyppi = tyyppi;
      el.classList.add('nakyy');
      clearTimeout(el._t);
      el._t = setTimeout(() => el.classList.remove('nakyy'), 3800);
    },

    tallenna(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* ei tallennusta */ } },
    lue(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  };

  window.TK = TK;
})();
