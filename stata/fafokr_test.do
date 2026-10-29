* Tester for fafokr. Kjør fra mappen med pakkefilene, eller etter installasjon:
*   cd "<mappen med fafokr.ado>"
*   do fafokr_test.do
* G-testene bruker ekte tall fra Nav. KPI- og lønnstestene hoppes over
* hvis tallene ikke er hentet ennå.

clear all
discard
set more off

* ---- G-enheter og tilbake ----------------------------------------------
set obs 4
gen aar = 2021 + _n
gen G_kjent = cond(aar == 2022, 109784, cond(aar == 2023, 116239, ///
              cond(aar == 2024, 122225, 128116)))
gen inntekt = 2 * G_kjent
label variable inntekt "Inntekt"

fafokr set inntekt, year(aar) status(løpende)
assert "`: char inntekt[fafokr_status]'" == "lopende"

fafokr convert inntekt, index(g_snitt) generate(g_)
assert reldif(g_inntekt, 2) < 1e-12
assert "`: char g_inntekt[fafokr_status]'" == "g"
assert "`: variable label g_inntekt'" == "Inntekt, G-enheter (gj.snittlig G)"

fafokr convert g_inntekt, index(nominell) generate(n_)
assert reldif(n_g_inntekt, inntekt) < 1e-12

fafokr convert inntekt, index(g) to(2025) generate(gj_)
assert reldif(gj_inntekt, 2 * 128116) < 1e-12
assert "`: char gj_inntekt[fafokr_base]'" == "2025"

* ---- G-variabler ---------------------------------------------------------
fafokr g aar, generate(G1)
assert G1 == G_kjent
fafokr g aar, generate(G2) type(mai)
assert G2 == 130160 if aar == 2025
assert G2 == 111477 if aar == 2022

gen dato = .
replace dato = mdy(4, 30, 2024) in 1
replace dato = mdy(5, 1, 2024) in 2
replace dato = mdy(12, 15, 1990) in 3
replace dato = mdy(12, 31, 1966) in 4
format dato %td
fafokr g dato, generate(G3) type(dato)
assert G3[1] == 118620 & G3[2] == 124028 & G3[3] == 34100 & missing(G3[4])

* ---- Faste kroner med G som deflator --------------------------------------
gen p15 = 1000
fafokr set p15, year(aar) status(fast) base(2015) deflator(g_snitt)
fafokr convert p15, index(nominell) generate(n_)
assert reldif(n_p15, 1000 * G_kjent / 89502) < 1e-12
fafokr convert p15, index(g_snitt) to(2016) generate(b16_)
assert reldif(b16_p15, 1000 * 91740 / 89502) < 1e-12

* ---- Replace og kjeding ---------------------------------------------------
gen long kopi = inntekt
fafokr set kopi, year(aar) status(lopende)
fafokr convert kopi, index(g_mai) replace
assert reldif(kopi, inntekt / G2) < 1e-12
assert "`: char kopi[fafokr_deflator]'" == "g_mai"

* ---- Feilmeldinger --------------------------------------------------------
rcof "fafokr convert inntekt, index(kpi) generate(x_)" == 198
rcof "fafokr convert inntekt, index(g_snitt)" == 198
rcof "fafokr set inntekt, year(aar) status(fast)" == 198
rcof "fafokr set inntekt, year(aar) status(lopende)" == 110
rcof "fafokr convert G_kjent, index(g_snitt) generate(x_)" == 459
rcof "fafokr convert inntekt, index(g_snitt) generate(g_)" == 110

fafokr describe

* ---- KPI og lønn, hvis hentet ---------------------------------------------
preserve
fafokr table aar, clear
quietly count if !missing(kpi)
local harkpi = r(N) > 0
quietly count if !missing(lonn)
local harlonn = r(N) > 0
quietly count if !missing(usd) & !missing(eur) & aar == 2022
local harvaluta = r(N) > 0
if `harvaluta' {
    quietly summarize usd if aar == 2022, meanonly
    local usd22 = r(mean)
}
restore

if `harkpi' {
    fafokr convert inntekt, index(kpi) to(2022) generate(r_)
    fafokr convert r_inntekt, index(nominell) generate(n_)
    assert reldif(n_r_inntekt, inntekt) < 1e-10
    assert reldif(r_inntekt, inntekt) < 1e-12 if aar == 2022
    * Fra KPI-kroner til G-enheter skal gi det samme som direkte
    fafokr convert r_inntekt, index(g_snitt) generate(g_)
    assert reldif(g_r_inntekt, g_inntekt) < 1e-10
    rcof "fafokr convert inntekt, index(kpi) to(1900) generate(z_)" == 459
}
else di as txt "KPI er ikke hentet ennå – hopper over KPI-testene."

if `harlonn' {
    fafokr convert inntekt, index(lonn) to(2022) generate(l_)
    fafokr convert l_inntekt, index(nominell) generate(n_)
    assert reldif(n_l_inntekt, inntekt) < 1e-10
}
else di as txt "Lønnsindeksen er ikke hentet ennå – hopper over lønnstestene."

if `harvaluta' {
    * Løpende kroner med årets kurs
    fafokr convert inntekt, index(nominell) currency(usd) generate(usd_)
    fafokr kurs aar, generate(usdkurs) currency(usd)
    assert reldif(usd_inntekt, inntekt / usdkurs) < 1e-12
    assert reldif(usdkurs, `usd22') < 1e-12 if aar == 2022
    assert "`: char usd_inntekt[fafokr_valuta]'" == "usd"
    * G-justerte kroner på 2022-nivå, deretter til USD med 2022-kursen
    fafokr convert inntekt, index(g_snitt) to(2022) currency(usd) generate(gusd_)
    assert reldif(gusd_inntekt, 2 * 109784 / `usd22') < 1e-12
    * Feil: G-enheter, ukjent valuta og variabel som allerede er i valuta
    rcof "fafokr convert inntekt, index(g_snitt) currency(usd) generate(x_)" == 198
    rcof "fafokr convert inntekt, index(nominell) currency(sek) generate(x_)" == 198
    rcof "fafokr convert usd_inntekt, index(nominell) generate(x_)" == 459
    fafokr describe
}
else di as txt "Valutakursene er ikke hentet ennå – hopper over valutatestene."

fafokr sources
di as res _n "Alle fafokr-tester gikk gjennom."
