# fafokr – kroner, G og indekser

`fafokr` regner om beløp til faste kroner med KPI eller lønnsindeks, til G-enheter eller til G-justerte kroner, og kan regne resultatet om til USD eller EUR. Pakken finnes for både R og Stata, med samme datagrunnlag og samme logikk.

Indeksene hentes fra Navs G-API (g.nav.no), SSBs statistikkbank (PxWebApi v2, tabell 14700 og 14710 for KPI og 09786 for påløpt årslønn) og Norges Banks åpne API (valutakurser, datasettet EXR). Repoet oppdaterer tallene automatisk den 15. hver måned. Begge pakkene har med seg tallene, så de virker også på servere uten nett.

> **Til vedlikeholder:** Bytt ut `Forskningsstiftelsen-Fafo` i denne filen med GitHub-brukernavnet eller organisasjonen repoet ligger under.

## Installasjon

**R** (ingen kompilering, Rtools trengs ikke):

```r
install.packages("remotes")
remotes::install_github("Forskningsstiftelsen-Fafo/fafokr", subdir = "r/fafokr")
library(fafokr)
fk_kilder()   # viser hva som er hentet og når
```

**Stata** (versjon 14 eller nyere):

```stata
net install fafokr, from("https://raw.githubusercontent.com/Forskningsstiftelsen-Fafo/fafokr/main/stata") replace
help fafokr
fafokr sources
```

En ny installasjon gir alltid de nyeste tallene i repoet.

## Få nye tall uten å installere på nytt

**R:** `fk_oppdater()` henter rett fra Nav, SSB og Norges Bank og lagrer i en lokal cache. Pakken bruker cachen når den er nyere enn tallene som fulgte med installasjonen.

**Stata:**

```stata
fafokr update, from("https://raw.githubusercontent.com/Forskningsstiftelsen-Fafo/fafokr/main/stata")
```

Kommandoen kontrollerer filene og legger dem i PERSONAL-mappen. Stata bruker dem foran tallene fra installasjonen så lenge de er nyere.

**Uten internett (f.eks. sikre servere):** Hent filene på en maskin med nett, med `fk_oppdater(mappe = "K:/Felles/fafokr")` i R eller ved å laste ned de fire CSV-filene i `stata/`. Flytt dem inn og kjør `fafokr update, from("<mappen>")`.

## Bruk

Først får variablene en status. Statusen sier om tallene er løpende kroner, faste kroner (med basisår og deflator) eller G-enheter, og hvilken variabel som gir året. Deretter regner `convert` om ut fra statusen.

| Stata | R | Hva |
|---|---|---|
| `fafokr set inntekt, year(aar) status(løpende)` | `d <- fk_set(d, inntekt, aar = aar, status = "løpende")` | Løpende kroner |
| `fafokr set p15, year(aar) status(fast) base(2015) deflator(kpi)` | `fk_set(d, p15, aar = aar, status = "fast", base = 2015, deflator = "kpi")` | Faste 2015-kroner, KPI |
| `fafokr convert inntekt, index(kpi) to(2025) generate(r_)` | `fk_convert(d, inntekt, "kpi", to = 2025, prefix = "r_")` | Faste 2025-kroner |
| `fafokr convert inntekt, index(lonn) to(2025) generate(l_)` | `fk_convert(d, inntekt, "lonn", to = 2025, prefix = "l_")` | Lønnsjustert til 2025 |
| `fafokr convert inntekt, index(g_snitt) generate(g_)` | `fk_convert(d, inntekt, "g_snitt", prefix = "g_")` | G-enheter |
| `fafokr convert inntekt, index(g_snitt) to(2025) generate(gj_)` | `fk_convert(d, inntekt, "g_snitt", to = 2025, prefix = "gj_")` | G-justerte 2025-kroner |
| `fafokr convert r_inntekt, index(nominell) generate(n_)` | `fk_convert(d, r_inntekt, "nominell", prefix = "n_")` | Tilbake til løpende kroner |
| `fafokr convert inntekt, index(kpi) to(2025) currency(eur) generate(eur_)` | `fk_convert(d, inntekt, "kpi", to = 2025, prefix = "eur_", currency = "eur")` | Faste 2025-kroner i EUR (2025-kurs) |
| `fafokr convert inntekt, index(nominell) currency(usd) generate(usd_)` | `fk_convert(d, inntekt, "nominell", prefix = "usd_", currency = "usd")` | Løpende USD (årets kurs) |
| `fafokr kurs aar, generate(usdkurs) currency(usd)` | `fk_kurs(aar, "usd")` | Valutakurs (NOK per USD) |
| `fafokr describe` | `fk_info(d)` | Vis status |
| `fafokr g aar, generate(G)` | `fk_g_aar(aar)` | Gjennomsnittlig G i året |
| `fafokr g aar, generate(G) type(mai)` | `fk_g_aar(aar, "mai")` | G per 1. mai |
| `fafokr g dato, generate(G) type(dato)` | `fk_g(dato)` | G som gjaldt på datoen |
| `fafokr table g, clear` | `fk_tabell("g")` | Tabellene |
| `fafokr sources` | `fk_kilder()` | Kilder og hentedatoer |

`replace` (Stata) og `replace = TRUE` (R) erstatter variablene i stedet for å lage nye. For én vektor i R finnes `fk_kr(x, aar, index, to, status, base, deflator, currency)`.

Regnereglene:

- Løpende kroner deflateres direkte: x · I(til) / I(år).
- Faste kroner med samme deflator som `index` flyttes bare til nytt basisår: x · I(til) / I(base).
- Faste kroner med en annen deflator blåses først opp til løpende kroner med den opprinnelige deflatoren og regnes så om. Det betyr at du kan gå fra KPI-kroner til G-enheter uten å gjøre noe galt.
- G-enheter ganges først med G for året.
- Med `currency` regnes resultatet om fra NOK til USD eller EUR til slutt. Faste kroner deles på kursen i `to`-året, så realverdien beholdes. Løpende kroner (`nominell`) deles på kursen for hvert år. G-enheter kan ikke regnes om til valuta, og en variabel som allerede er i valuta, kan ikke regnes om igjen.
- Mangler indeksen for et år, blir resultatet manglende, og antallet rapporteres. Mangler den for målåret eller basisåret, stopper kommandoen med en melding om hvilke år som finnes.

Nye variabler får selv status, så omregninger kan kjedes. I Stata lagres statusen som karakteristikker (`char`) og følger med .dta-filen. I R lagres den som attributt på kolonnen. Noen operasjoner i R (for eksempel subsetting med `[`) fjerner attributter. Da stopper `fk_convert()` med beskjed om å kjøre `fk_set()` på nytt, i stedet for å regne feil.

## Om tallene

- **G:** Navs grunnbeløp med alle endringer siden 1967. `g_snitt` er Navs gjennomsnitt per år, og pakken kontrollerer at det stemmer med snittet av G den 1. i hver måned. `g_mai` er G som gjaldt 1. mai.
- **KPI:** totalindeksen (2025=100) per måned fra tabell 14700, som starter i januar 2000. Månedene før 2000 hentes fra SSBs historiske serie i tabell 14710 (fra 1920) og skjøtes på med overlappet i 2000, slik at hele serien har samme nivå. Begge tabellene har 2025=100, så skjøtefaktoren er nær 1. Årstallet er snittet av de tolv månedene og lages bare for hele år. Det kan avvike med 0,1 fra SSBs publiserte, avrundede årsgjennomsnitt. Tabell 03013 (2015=100), som pakken brukte før versjon 1.0.1, oppdateres ikke lenger.
- **Valutakurser:** årsgjennomsnitt av Norges Banks daglige kurser, i NOK per USD og NOK per EUR. Bare hele år tas med. Euro finnes fra 1999. Dette er markedskurser. For sammenligninger av levestandard mellom land kan kjøpekraftsjusterte kurser (PPP) være et bedre valg.
- **Lønnsindeks:** indeksen for påløpt årslønn for alle lønnstakere (2010=100) fra nasjonalregnskapet, tabell 09786. Indeksen er avrundet til én desimal, så veksten mellom to år kan avvike med 0,1 prosentpoeng fra SSBs publiserte vekstrate. Tallene kan revideres, så oppgi hentedatoen i metodedelen (`fk_kilder()` / `fafokr sources`).

## Innhold i repoet

```
README.md
.github/workflows/oppdater-indekser.yml   månedlig oppdatering
r/fafokr/                                 R-pakken (kildekode)
  ├── inst/extdata/                       tallene R-pakken har med seg
  └── data-raw/oppdater_indekser.R        henter tall til begge pakkene
stata/
  ├── fafokr.ado, fafokr.sthlp, fafokr.pkg, stata.toc
  ├── fafokr_aar.csv, fafokr_g.csv, fafokr_kpi_mnd.csv, fafokr_kilder.csv
  └── fafokr_test.do
```

## Automatisk oppdatering (for vedlikeholder)

Arbeidsflyten i `.github/workflows/oppdater-indekser.yml` kjører den 15. hver måned kl. 06 UTC. Den henter G, KPI, lønnsindeks og valutakurser, kontrollerer tallene og skriver de samme fire CSV-filene til `r/fafokr/inst/extdata/` og `stata/`. Endringene lagres som en commit kalt «Oppdaterte indekser ÅÅÅÅ-MM-DD».

Hvis én av hentingene feiler, stopper jobben uten å endre noe, og GitHub sender e-post. Da er tallene i repoet fortsatt de forrige, gyldige tallene.

**Oppsett første gang:**

1. Repoet må være **Public**, slik at Stata kan installere og oppdatere fra det. Det ligger ingen hemmeligheter i pakken.
2. Gå til **Settings → Actions → General → Workflow permissions**, velg **Read and write permissions** og lagre.
3. Gå til **Actions → Oppdater indekser → Run workflow**. Etter et par minutter skal kjøringen være grønn, og det skal ligge en ny commit med KPI og lønnsindeks i CSV-filene. Gjør dette rett etter opplasting, siden repoet ellers bare har G fram til første planlagte kjøring.

**Godt å vite:**

- Hentedatoen endres ved hver kjøring, så det blir en commit hver måned selv når SSB ikke har publisert nye tall.
- GitHub setter planlagte kjøringer på pause i repoer som ikke har hatt aktivitet på 60 dager. Da kommer det e-post, og arbeidsflyten kan slås på igjen under **Actions**.
- Oppdateringen kan også kjøres lokalt fra roten av repoet: `Rscript r/fafokr/data-raw/oppdater_indekser.R`.
- Når R- eller Stata-koden endres, økes versjonsnummeret (nå 1.0.1) i `r/fafokr/DESCRIPTION`, i første linje av `stata/fafokr.ado` og i andre linje av `stata/fafokr.sthlp`, og datoen i `Distribution-Date` i `stata/fafokr.pkg` oppdateres. Rettelser øker det siste tallet (1.0.1), nye funksjoner det midterste (1.1.0), og endringer som kan få eksisterende kode til å regne annerledes eller slutte å virke, det første (2.0.0).

## Testet

- R-pakken består `R CMD check` uten merknader og har 21 tester med 113 kontroller. G er testet mot Navs data, SSB-hentingen mot svar i JSON-stat2-formatet og Norges Bank-hentingen mot svar i API-ets CSV-format.
- Stata-pakken er testet med `stata/fafokr_test.do` (G, KPI, lønnsindeks, valuta, rundturer og feilmeldinger). Kjør den gjerne etter en ny installasjon.
