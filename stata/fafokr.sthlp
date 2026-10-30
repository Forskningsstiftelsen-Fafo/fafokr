{smcl}
{* *! version 1.0.1  30okt2026}{...}
{title:Tittel}

{phang}
{bf:fafokr} {hline 2} Kroner, G og indekser: faste kroner med KPI eller lønnsindeks,
G-enheter, G-justerte kroner og valuta (USD, EUR)


{title:Syntaks}

{p 8 16 2}
{cmd:fafokr set} {varlist}{cmd:,} {opt y:ear(varname)} {opt s:tatus(status)}
[{opt b:ase(#)} {opt d:eflator(indeks)} {opt replace}]

{p 8 16 2}
{cmd:fafokr convert} {varlist}{cmd:,} {opt i:ndex(indeks)}
[{opt t:o(#)} {opt cur:rency(usd|eur)} {opt gen:erate(prefiks)} {opt replace}]

{p 8 16 2}
{cmd:fafokr describe} [{varlist}]

{p 8 16 2}
{cmd:fafokr g} {varname}{cmd:,} {opt gen:erate(newvar)} [{opt t:ype(snitt|mai|dato)}]

{p 8 16 2}
{cmd:fafokr kurs} {varname}{cmd:,} {opt gen:erate(newvar)} {opt cur:rency(usd|eur)}

{p 8 16 2}
{cmd:fafokr table} [{cmd:aar}|{cmd:g}|{cmd:kpi_mnd}|{cmd:kilder}] [{cmd:,} {opt clear}]

{p 8 16 2}
{cmd:fafokr sources}

{p 8 16 2}
{cmd:fafokr update}{cmd:,} {opt from(mappe eller URL)}


{title:Beskrivelse}

{pstd}
{cmd:fafokr} regner om beløp med konsumprisindeksen (KPI), lønnsindeksen eller
grunnbeløpet i folketrygden (G). Hver variabel får først en {it:status} med
{cmd:fafokr set}. Statusen sier om tallene er løpende kroner, faste kroner
(med basisår og deflator) eller G-enheter, og hvilken variabel som gir året.
{cmd:fafokr convert} bruker statusen til å regne riktig, også når tallene
allerede er deflatert med en annen indeks eller til et annet år enn ønsket.

{pstd}
Statusen lagres som {help char:karakteristikker} på variabelen og følger med
når dataene lagres. Nye variabler fra {cmd:fafokr convert} får selv status, så
omregninger kan kjedes.

{pstd}
Indeksene kommer fra Navs G-API (g.nav.no) og SSBs statistikkbank (tabell 14700
for KPI, med den historiske serien i tabell 14710 for årene før 2000, og 09786
for lønnsindeksen). Valutakursene er årsgjennomsnitt fra Norges
Banks åpne API (datasettet EXR). Pakken har med seg et øyeblikksbilde av
tabellene. {cmd:fafokr update} henter nyere filer fra en mappe eller URL der
noen har lagt dem med R-funksjonen {cmd:fk_oppdater()}. Se
{cmd:fafokr sources} for hentedatoer.


{title:Status ({cmd:fafokr set})}

{phang}
{opt status(løpende)} Nominelle kroner i året i {opt year()}. Også {cmd:lopende}
og {cmd:nominell} godtas.

{phang}
{opt status(fast)} Faste kroner. Krever {opt base()} (basisåret) og
{opt deflator()}: indeksen tallene ble deflatert med ({cmd:kpi}, {cmd:lonn},
{cmd:g_snitt} eller {cmd:g_mai}).

{phang}
{opt status(g)} G-enheter (beløp delt på G). {opt deflator()} er {cmd:g_snitt}
(standard) eller {cmd:g_mai}.

{phang}
{opt replace} overskriver en status som finnes fra før.


{title:Indekser ({cmd:fafokr convert})}

{phang}
{cmd:index(kpi) to(}{it:år}{cmd:)} Faste {it:år}-kroner deflatert med KPI
(årsgjennomsnitt, 2025=100).

{phang}
{cmd:index(lonn) to(}{it:år}{cmd:)} Beløpene lønnsjustert til {it:år}-nivå med
indeksen for påløpt årslønn for alle lønnstakere (nasjonalregnskapet,
2010=100).

{phang}
{cmd:index(g_snitt)} G-enheter: beløpet delt på gjennomsnittlig G i året.
{cmd:index(g_mai)} bruker G per 1. mai. Med {opt to(år)} blir resultatet i
stedet G-justerte kroner på {it:år}-nivå.

{phang}
{cmd:index(nominell)} Tilbake til løpende kroner.

{pstd}
Omregningen går slik: faste kroner med samme deflator som {opt index()} flyttes
bare til nytt basisår. Ellers blåses beløpet først opp til løpende kroner med
den opprinnelige deflatoren og regnes så om med {opt index()}. Beløp i år
der indeksen mangler, får manglende verdi, og antallet vises.

{phang}
{opt currency(usd|eur)} regner resultatet om fra NOK til dollar eller euro med
årsgjennomsnittet av Norges Banks kurs. Faste kroner (med {opt to()}) deles på
kursen i {opt to()}-året, slik at realverdien beholdes. Løpende kroner
({cmd:index(nominell)}) deles på kursen for hvert år. Valuta kan ikke kombineres
med G-enheter, og en variabel som allerede er i valuta, kan ikke regnes om igjen.
Merk at dette er markedskurser, ikke kjøpekraftsjusterte kurser (PPP).

{phang}
{opt generate(prefiks)} lager nye variabler med prefikset foran navnet.
{opt replace} erstatter variablene. Én av dem må oppgis.


{title:G-variabler ({cmd:fafokr g})}

{pstd}
Lager en variabel med G. Med {cmd:type(snitt)} (standard) eller {cmd:type(mai)}
er {it:varname} et årstall. Med {cmd:type(dato)} er {it:varname} en daglig dato
({cmd:%td}), og variabelen får G som gjaldt den dagen. Bruk {cmd:dofm()} først
hvis datoen er månedlig.


{title:Valutakurser ({cmd:fafokr kurs})}

{pstd}
Lager en variabel med årsgjennomsnittet av valutakursen (NOK per USD eller EUR)
for årstallet i {it:varname}. Kursen for euro finnes fra 1999.


{title:Eksempler}

{pstd}Løpende inntekt i faste 2025-kroner og i G-enheter:{p_end}
{phang2}{cmd:. fafokr set inntekt lonn, year(aar) status(løpende)}{p_end}
{phang2}{cmd:. fafokr convert inntekt lonn, index(kpi) to(2025) generate(r_)}{p_end}
{phang2}{cmd:. fafokr convert inntekt, index(g_snitt) generate(g_)}{p_end}

{pstd}Pensjon som allerede er i faste 2015-kroner (KPI), i G-enheter:{p_end}
{phang2}{cmd:. fafokr set pensjon15, year(aar) status(fast) base(2015) deflator(kpi)}{p_end}
{phang2}{cmd:. fafokr convert pensjon15, index(g_snitt) generate(g_)}{p_end}

{pstd}Inntekt i faste 2025-kroner omregnet til euro, og løpende inntekt i dollar:{p_end}
{phang2}{cmd:. fafokr convert inntekt, index(kpi) to(2025) currency(eur) generate(eur_)}{p_end}
{phang2}{cmd:. fafokr convert inntekt, index(nominell) currency(usd) generate(usd_)}{p_end}
{phang2}{cmd:. fafokr kurs aar, generate(usdkurs) currency(usd)}{p_end}

{pstd}Se status, kilder og G-tabellen:{p_end}
{phang2}{cmd:. fafokr describe}{p_end}
{phang2}{cmd:. fafokr sources}{p_end}
{phang2}{cmd:. fafokr table g, clear}{p_end}

{pstd}Hent nye tall fra en delt mappe:{p_end}
{phang2}{cmd:. fafokr update, from("K:/Felles/fafokr")}{p_end}


{title:Lagrede resultater}

{pstd}{cmd:fafokr convert} lagrer i {cmd:r()}:{p_end}
{synoptset 15 tabbed}{...}
{synopt:{cmd:r(varlist)}}nye eller erstattede variabler{p_end}
{synopt:{cmd:r(index)}}indeksen som ble brukt{p_end}
{synopt:{cmd:r(to)}}måleåret{p_end}
{synopt:{cmd:r(currency)}}valutaen, hvis {opt currency()} er brukt{p_end}
{synopt:{cmd:r(kilde)}}kilde og hentedato for indeksen{p_end}
{synopt:{cmd:r(dir)}}mappen datagrunnlaget ble lest fra{p_end}


{title:Datagrunnlag}

{pstd}
Fire CSV-filer: {cmd:fafokr_aar.csv} (én rad per år med {cmd:g_snitt},
{cmd:g_mai}, {cmd:kpi}, {cmd:lonn}, {cmd:usd} og {cmd:eur}), {cmd:fafokr_g.csv} (perioder med G),
{cmd:fafokr_kpi_mnd.csv} og {cmd:fafokr_kilder.csv}. Pakken leser fra
PERSONAL-mappen hvis {cmd:fafokr update} har lagt nyere filer der, og ellers
fra mappen pakken ble installert i. KPI-årstallene er gjennomsnitt av SSBs
månedstall og kan avvike med 0,1 fra SSBs avrundede årsgjennomsnitt.


{title:Se også}

{pstd}
R-pakken {cmd:fafokr} har de samme funksjonene ({cmd:fk_set()},
{cmd:fk_convert()}, {cmd:fk_g()}, {cmd:fk_kurs()}, {cmd:fk_oppdater()}).
{p_end}
