// Kuvaraportti (PDF) työmaan dokumentoinnista. Käytetään hallinnassa ja asiakkaan sivulla.
// Kuvat: [{ vaihe, kommentti, otettu, url, leveys, korkeus }], url = ison kuvan osoite.
(function () {
  const JSPDF = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';
  const MUSTA = [28, 27, 25], HARMAA = [107, 102, 92], VIIVA = [214, 207, 195], SAVI = [139, 90, 60];

  function lataaSkripti(src) {
    return new Promise((ok, ei) => {
      if (window.jspdf) return ok();
      const s = document.createElement('script'); s.src = src; s.onload = ok; s.onerror = () => ei(new Error('PDF-kirjasto ei latautunut.'));
      document.head.appendChild(s);
    });
  }

  async function kuvaDataksi(url) {
    const r = await fetch(url);
    if (!r.ok) throw new Error('Kuvaa ei saatu ladattua.');
    const blob = await r.blob();
    const data = await new Promise((ok, ei) => { const f = new FileReader(); f.onload = () => ok(f.result); f.onerror = ei; f.readAsDataURL(blob); });
    const koko = await new Promise(ok => { const i = new Image(); i.onload = () => ok({ w: i.naturalWidth, h: i.naturalHeight }); i.onerror = () => ok({ w: 4, h: 3 }); i.src = data; });
    return { data, ...koko };
  }

  // PDF:n vakiofontit tukevat ä/ö/å, mutta eivät kaikkia erikoismerkkejä
  const siisti = t => String(t || '').replace(/[–—]/g, '-').replace(/[→]/g, '->').replace(/[“”„]/g, '"').replace(/[‘’]/g, "'");
  const kpl = n => `${n} ${n === 1 ? 'kuva' : 'kuvaa'}`;

  async function luo({ tyomaa, kuvat, yritys = 'Brothers & Co.', tiedosto, eteneminen }) {
    await lataaSkripti(JSPDF);
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF({ unit: 'mm', format: 'a4' });
    const W = 210, H = 297, M = 18, SARAKE = (W - 2 * M - 8) / 2, VALI = 8, ALA = H - 20;
    const pvm = d => TK.pvm(d), aika = d => TK.aika(d);
    const vari = (c, t = 'text') => (t === 'text' ? doc.setTextColor(...c) : doc.setDrawColor(...c));
    let y = M;

    // Otsikko-osa
    doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); vari(MUSTA);
    doc.setCharSpace(.9);
    doc.text(siisti(yritys.toUpperCase()), M, y + 2);
    doc.setCharSpace(0);
    vari(HARMAA);
    doc.text(`Raportti ${pvm(new Date())}`, W - M, y + 2, { align: 'right' });
    vari(VIIVA, 'draw'); doc.setLineWidth(.2); doc.line(M, y + 6, W - M, y + 6);
    y += 20;
    doc.setFontSize(7); vari(HARMAA); doc.setCharSpace(.6);
    doc.text('TYÖN DOKUMENTOINTI', M, y);
    doc.setCharSpace(0);
    y += 12;

    doc.setFont('times', 'normal'); doc.setFontSize(30); vari(MUSTA);
    const nimi = doc.splitTextToSize(siisti(tyomaa.nimi), W - 2 * M);
    doc.text(nimi, M, y); y += nimi.length * 11 + 4;

    // Tietorivi: osoite, asiakas, ajanjakso
    const ryhmat = new Map();
    for (const k of [...kuvat].sort((a, b) => new Date(a.otettu) - new Date(b.otettu))) {
      if (!ryhmat.has(k.vaihe)) ryhmat.set(k.vaihe, []);
      ryhmat.get(k.vaihe).push(k);
    }
    const ajat = kuvat.map(k => new Date(k.otettu)).sort((a, b) => a - b);
    const vali = ajat.length ? (pvm(ajat[0]) === pvm(ajat[ajat.length - 1]) ? pvm(ajat[0]) : `${pvm(ajat[0])} - ${pvm(ajat[ajat.length - 1])}`) : '';
    const tiedot = [['OSOITE', tyomaa.osoite], ['ASIAKAS', tyomaa.asiakas], ['AJANJAKSO', vali],
      ['SISÄLTÖ', `${ryhmat.size} ${ryhmat.size === 1 ? 'työvaihe' : 'työvaihetta'}, ${kpl(kuvat.length)}`]].filter(x => x[1]);
    vari(VIIVA, 'draw'); doc.line(M, y, W - M, y); y += 6;
    const lev = (W - 2 * M) / Math.max(tiedot.length, 1);
    let korkein = 0;
    tiedot.forEach(([otsikko, arvo], i) => {
      const x = M + i * lev;
      doc.setFont('helvetica', 'normal'); doc.setFontSize(6.5); vari(HARMAA); doc.setCharSpace(.4);
      doc.text(otsikko, x, y); doc.setCharSpace(0);
      doc.setFontSize(9); vari(MUSTA);
      const r = doc.splitTextToSize(siisti(arvo), lev - 4);
      doc.text(r, x, y + 5);
      korkein = Math.max(korkein, 5 + r.length * 4);
    });
    y += korkein + 10;

    // Kuvat työvaiheittain (vaiheet ensimmäisen kuvan mukaan aikajärjestyksessä)
    let tehty = 0, n = 0;
    for (const [vaihe, lista] of ryhmat) {
      n++;
      if (y + 16 + SARAKE * 3 / 4 + 22 > ALA) { doc.addPage(); y = M + 4; }   // otsikko ja ensimmäinen kuvarivi samalle sivulle
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8); vari(HARMAA);
      doc.text(String(n).padStart(2, '0'), M, y + 6);
      doc.setFont('times', 'normal'); doc.setFontSize(19); vari(MUSTA);
      doc.text(siisti(vaihe), M + 9, y + 6.5);
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8); vari(HARMAA);
      doc.text(kpl(lista.length), W - M, y + 6, { align: 'right' });
      vari(VIIVA, 'draw'); doc.line(M, y + 10, W - M, y + 10);
      y += 16;
      let sarake = 0, rivinKorkeus = 0;
      for (const k of lista) {
        const kuva = await kuvaDataksi(k.url);
        // Kuvat samankokoisiin 4:3-kehyksiin; pystykuva näytetään kokonaan kehyksen keskellä
        const kh = SARAKE * 3 / 4, suhde = kuva.w / kuva.h;
        const iw = suhde > 4 / 3 ? SARAKE : kh * suhde, ih = suhde > 4 / 3 ? SARAKE / suhde : kh;
        doc.setFontSize(7.5);
        const aikaTeksti = `${pvm(k.otettu)}  ·  klo ${aika(k.otettu)}`;
        const kommentti = k.kommentti ? doc.splitTextToSize(siisti(k.kommentti), SARAKE) : [];
        const tarve = kh + 6 + 3.6 + kommentti.length * 3.8 + 8;
        if (sarake === 0 && y + tarve > ALA) { doc.addPage(); y = M + 4; }
        const x = M + sarake * (SARAKE + VALI);
        doc.setFillColor(238, 234, 226); doc.rect(x, y, SARAKE, kh, 'F');
        doc.addImage(kuva.data, 'JPEG', x + (SARAKE - iw) / 2, y + (kh - ih) / 2, iw, ih, undefined, 'FAST');
        doc.setFont('helvetica', 'normal'); doc.setFontSize(7); vari(HARMAA);
        doc.text(siisti(aikaTeksti), x, y + kh + 5);
        if (kommentti.length) { doc.setFontSize(8.5); vari(MUSTA); doc.text(kommentti, x, y + kh + 9.5); }
        rivinKorkeus = Math.max(rivinKorkeus, tarve);
        sarake++;
        if (sarake === 2) { sarake = 0; y += rivinKorkeus; rivinKorkeus = 0; }
        tehty++;
        if (eteneminen) eteneminen(tehty, kuvat.length);
      }
      if (sarake === 1) { y += rivinKorkeus; }
      y += 8;
    }

    // Alatunniste ja sivunumerot
    const sivuja = doc.getNumberOfPages();
    for (let i = 1; i <= sivuja; i++) {
      doc.setPage(i);
      vari(VIIVA, 'draw'); doc.setLineWidth(.2); doc.line(M, H - 13, W - M, H - 13);
      doc.setFont('helvetica', 'normal'); doc.setFontSize(7); vari(HARMAA);
      doc.text(siisti(`${yritys}  ·  ${tyomaa.nimi}`), M, H - 8.5);
      doc.text(`${i} / ${sivuja}`, W - M, H - 8.5, { align: 'right' });
      vari(SAVI, 'draw'); doc.setLineWidth(.6); doc.line(M, H - 13, M + 12, H - 13);
    }
    doc.save(tiedosto || `dokumentointi_${(tyomaa.nimi || 'tyomaa').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-')}.pdf`);
  }

  window.TKRaportti = { luo };
})();
