# fafokr – kroner, G og indekser

`fafokr` regner om beløp til faste kroner med KPI eller lønnsindeks, til G-enheter eller til G-justerte kroner. Pakken finnes for både R og Stata, med samme datagrunnlag og samme logikk.

Indeksene hentes fra Navs G-API (g.nav.no) og SSBs statistikkbank (PxWebApi v2, tabell 03013 for KPI og 09786 for påløpt årslønn). Repoet oppdaterer tallene automatisk den 15. hver måned. Begge pakkene har med seg tallene, så de virker også på servere uten nett.

> **Til vedlikeholder:** Bytt ut `BRUKER` i denne filen med GitHub-brukernavnet eller organisasjonen repoet ligger under.

## Installasjon

**R** (ingen kompilering, Rtools trengs ikke):

```r
install.packages("remotes")
remotes::install_github("BRUKER/fafokr", subdir = "r/fafokr")
library(fafokr)
fk_kilder()   # viser hva som er hentet og når
```

**Stata** (versjon 14 eller nyere):

```stata
net install fafokr, from("https://raw.githubusercontent.com/BRUKER/fafokr/main/stata") replace
help fafokr
fafokr sources
```

En ny installasjon gir alltid de nyeste tallene i repoet.

## Få nye tall uten å installere på nytt

**R:** `fk_oppdater()` henter rett fra Nav og SSB og lagrer i en lokal cache. Pakken bruker cachen når den er nyere enn tallene som fulgte med installasjonen.

**Stata:**

```stata
fafokr update, from("https://raw.githubusercontent.com/BRUKER/fafokr/main/stata")
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
| `fafokr describe` | `fk_info(d)` | Vis status |
| `fafokr g aar, generate(G)` | `fk_g_aar(aar)` | Gjennomsnittlig G i året |
| `fafokr g aar, generate(G) type(mai)` | `fk_g_aar(aar, "mai")` | G per 1. mai |
| `fafokr g dato, generate(G) type(dato)` | `fk_g(dato)` | G som gjaldt på datoen |
| `fafokr table g, clear` | `fk_tabell("g")` | Tabellene |
| `fafokr sources` | `fk_kilder()` | Kilder og hentedatoer |

`replace` (Stata) og `replace = TRUE` (R) erstatter variablene i stedet for å lage nye. For én vektor i R finnes `fk_kr(x, aar, index, to, status, base, deflator)`.

Regnereglene:

- Løpende kroner deflateres direkte: x · I(til) / I(år).
- Faste kroner med samme deflator som `index` flyttes bare til nytt basisår: x · I(til) / I(base).
- Faste kroner med en annen deflator blåses først opp til løpende kroner med den opprinnelige deflatoren og regnes så om. Det betyr at du kan gå fra KPI-kroner til G-enheter uten å gjøre noe galt.
- G-enheter ganges først med G for året.
- Mangler indeksen for et år, blir resultatet manglende, og antallet rapporteres. Mangler den for målåret eller basisåret, stopper kommandoen med en melding om hvilke år som finnes.

Nye variabler får selv status, så omregninger kan kjedes. I Stata lagres statusen som karakteristikker (`char`) og følger med .dta-filen. I R lagres den som attributt på kolonnen. Noen operasjoner i R (for eksempel subsetting med `[`) fjerner attributter. Da stopper `fk_convert()` med beskjed om å kjøre `fk_set()` på nytt, i stedet for å regne feil.

## Om tallene

- **G:** Navs grunnbeløp med alle endringer siden 1967. `g_snitt` er Navs gjennomsnitt per år, og pakken kontrollerer at det stemmer med snittet av G den 1. i hver måned. `g_mai` er G som gjaldt 1. mai.
- **KPI:** totalindeksen (2015=100) per måned fra tabell 03013. Årstallet er snittet av de tolv månedene og lages bare for hele år. Det kan avvike med 0,1 fra SSBs publiserte, avrundede årsgjennomsnitt.
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

Arbeidsflyten i `.github/workflows/oppdater-indekser.yml` kjører den 15. hver måned kl. 06 UTC. Den henter G, KPI og lønnsindeks, kontrollerer tallene og skriver de samme fire CSV-filene til `r/fafokr/inst/extdata/` og `stata/`. Endringene lagres som en commit kalt «Oppdaterte indekser ÅÅÅÅ-MM-DD».

Hvis én av hentingene feiler, stopper jobben uten å endre noe, og GitHub sender e-post. Da er tallene i repoet fortsatt de forrige, gyldige tallene.

**Oppsett første gang:**

1. Repoet må være **Public**, slik at Stata kan installere og oppdatere fra det. Det ligger ingen hemmeligheter i pakken.
2. Gå til **Settings → Actions → General → Workflow permissions**, velg **Read and write permissions** og lagre.
3. Gå til **Actions → Oppdater indekser → Run workflow**. Etter et par minutter skal kjøringen være grønn, og det skal ligge en ny commit med KPI og lønnsindeks i CSV-filene. Gjør dette rett etter opplasting, siden repoet ellers bare har G fram til første planlagte kjøring.

**Godt å vite:**

- Hentedatoen endres ved hver kjøring, så det blir en commit hver måned selv når SSB ikke har publisert nye tall.
- GitHub setter planlagte kjøringer på pause i repoer som ikke har hatt aktivitet på 60 dager. Da kommer det e-post, og arbeidsflyten kan slås på igjen under **Actions**.
- Oppdateringen kan også kjøres lokalt fra roten av repoet: `Rscript r/fafokr/data-raw/oppdater_indekser.R`.
- Når R- eller Stata-koden endres, bør versjonsnummeret økes i `r/fafokr/DESCRIPTION`, i første linje av `stata/fafokr.ado` og i `Distribution-Date` i `stata/fafokr.pkg`.

## Testet

- R-pakken består `R CMD check` uten merknader og har 14 tester med 74 kontroller. G er testet mot Navs data, og SSB-hentingen er testet mot svar i JSON-stat2-formatet.
- Stata-pakken er testet med `stata/fafokr_test.do` (G, KPI, lønnsindeks, rundturer og feilmeldinger). Kjør den gjerne etter en ny installasjon.
