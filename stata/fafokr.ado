*! version 0.1.0  28okt2026  Fafo
*! fafokr: kroner, G og indekser. Faste kroner med KPI eller lønnsindeks,
*! G-enheter og G-justerte kroner med grunnbeløpet i folketrygden.
*!
*! Underkommandoer:
*!   fafokr set      varlist, year() status() [base() deflator() replace]
*!   fafokr convert  varlist, index() [to() generate() replace]
*!   fafokr describe [varlist]
*!   fafokr g        varname, generate() [type(snitt|mai|dato)]
*!   fafokr table    [aar|g|kpi_mnd|kilder] [, clear]
*!   fafokr sources
*!   fafokr update   , from()

program define fafokr, rclass
    version 14
    gettoken sub 0 : 0, parse(" ,")
    local sub = ustrlower(`"`sub'"')
    if `"`sub'"' == "" {
        di as err "Oppgi en underkommando: set, convert, describe, g, table, sources eller update."
        exit 198
    }
    if "`sub'" == "set" {
        fafokr_set `0'
    }
    else if inlist("`sub'", "convert", "konverter", "conv") {
        fafokr_convert `0'
    }
    else if inlist("`sub'", "describe", "desc", "d") {
        fafokr_describe `0'
    }
    else if "`sub'" == "g" {
        fafokr_g `0'
    }
    else if inlist("`sub'", "table", "tabell") {
        fafokr_table `0'
    }
    else if inlist("`sub'", "sources", "kilder") {
        fafokr_sources `0'
    }
    else if inlist("`sub'", "update", "oppdater") {
        fafokr_update `0'
    }
    else {
        di as err `"Ukjent underkommando "`sub'". Se {help fafokr}."'
        exit 198
    }
    return add
end

* ---------------------------------------------------------------------------
* fafokr set: gi variabler status
* ---------------------------------------------------------------------------
program define fafokr_set, rclass
    syntax varlist(numeric), Year(varname numeric) Status(string) ///
        [Base(numlist integer max=1) Deflator(string) REPLACE]

    fafokr__normstatus `"`status'"'
    local status `r(status)'
    if "`deflator'" != "" {
        fafokr__normindex `"`deflator'"'
        local deflator `r(index)'
    }

    if "`status'" == "lopende" {
        if "`base'`deflator'" != "" {
            di as err "base() og deflator() skal ikke oppgis for løpende kroner."
            exit 198
        }
    }
    else if "`status'" == "fast" {
        if "`base'" == "" | "`deflator'" == "" {
            di as err "Faste kroner krever både base() (basisår) og deflator() (kpi, lonn, g_snitt eller g_mai)."
            exit 198
        }
        if !inlist("`deflator'", "kpi", "lonn", "g_snitt", "g_mai") {
            di as err "deflator() må være kpi, lonn, g_snitt eller g_mai."
            exit 198
        }
    }
    else if "`status'" == "g" {
        if "`base'" != "" {
            di as err "base() skal ikke oppgis for G-enheter."
            exit 198
        }
        if "`deflator'" == "" local deflator g_snitt
        if !inlist("`deflator'", "g_snitt", "g_mai") {
            di as err "For G-enheter må deflator() være g_snitt eller g_mai."
            exit 198
        }
    }
    else {
        di as err `"Ukjent status "`status'". Bruk løpende, fast eller g."'
        exit 198
    }

    local i : list posof "`year'" in varlist
    if `i' {
        di as err "Årsvariabelen `year' kan ikke selv få status."
        exit 198
    }
    foreach v of local varlist {
        local gml : char `v'[fafokr_status]
        if "`gml'" != "" & "`replace'" == "" {
            local gb : char `v'[fafokr_base]
            local gd : char `v'[fafokr_deflator]
            fafokr__beskriv `gml' "`gb'" "`gd'"
            di as err "`v' har allerede status (`r(tekst)'). Bruk replace."
            exit 110
        }
    }

    foreach v of local varlist {
        local orig : char `v'[fafokr_label]
        if `"`orig'"' == "" {
            local orig : variable label `v'
            if `"`orig'"' == "" local orig `v'
        }
        char `v'[fafokr_status] `status'
        char `v'[fafokr_year] `year'
        char `v'[fafokr_base] `base'
        char `v'[fafokr_deflator] `deflator'
        char `v'[fafokr_label] `orig'
    }
    fafokr__beskriv `status' "`base'" "`deflator'"
    di as txt "fafokr: " as res "`varlist'" as txt " = " as res "`r(tekst)'" ///
        as txt " (år i " as res "`year'" as txt ")"
    return local varlist `varlist'
    return local status `status'
end

* ---------------------------------------------------------------------------
* fafokr convert: regn om
* ---------------------------------------------------------------------------
program define fafokr_convert, rclass
    syntax varlist(numeric), Index(string) ///
        [To(numlist integer max=1) GENerate(name) REPLACE]

    fafokr__normindex `"`index'"'
    local index `r(index)'
    if !inlist("`index'", "kpi", "lonn", "g_snitt", "g_mai", "nominell") {
        di as err "index() må være kpi, lonn, g_snitt, g_mai eller nominell."
        exit 198
    }
    if inlist("`index'", "kpi", "lonn") & "`to'" == "" {
        di as err "Oppgi to() (året beløpene skal uttrykkes i) med index(`index')."
        exit 198
    }
    if "`index'" == "nominell" & "`to'" != "" {
        di as err "to() skal ikke oppgis med index(nominell)."
        exit 198
    }
    if ("`generate'" == "") == ("`replace'" == "") {
        di as err "Oppgi enten generate(prefiks) eller replace."
        exit 198
    }
    local gunits = inlist("`index'", "g_snitt", "g_mai") & "`to'" == ""

    * Les og kontroller status for hver variabel
    local years
    local i 0
    foreach v of local varlist {
        local ++i
        local s`i' : char `v'[fafokr_status]
        local y`i' : char `v'[fafokr_year]
        local b`i' : char `v'[fafokr_base]
        local d`i' : char `v'[fafokr_deflator]
        local l`i' : char `v'[fafokr_label]
        if "`s`i''" == "" {
            di as err "`v' har ingen fafokr-status. Bruk {cmd:fafokr set} først."
            exit 459
        }
        capture confirm numeric variable `y`i''
        if _rc {
            di as err "Årsvariabelen `y`i'' for `v' finnes ikke (eller er ikke numerisk)."
            exit 111
        }
        if "`generate'" != "" {
            local nv`i' `generate'`v'
            confirm new variable `nv`i''
        }
        else local nv`i' `v'
        local years `years' `y`i''
    }
    local nvars `i'
    local years : list uniq years

    * Hent indekstabellen, slå opp faste faktorer og legg tabellen i Mata
    tempname K
    preserve
    fafokr__load aar
    local dir `"`r(dir)'"'
    if "`index'" != "nominell" fafokr__sjekkserie `index'
    if "`to'" != "" {
        fafokr__oppslag `index' `to'
        scalar `K' = r(val)
    }
    forvalues i = 1/`nvars' {
        if inlist("`s`i''", "fast", "g") fafokr__sjekkserie `d`i''
        if "`s`i''" == "fast" {
            tempname B`i'
            fafokr__oppslag `d`i'' `b`i''
            scalar `B`i'' = r(val)
        }
    }
    mata: fafokr__T = st_data(., "aar kpi lonn g_snitt g_mai")
    if "`index'" != "nominell" {
        fafokr__kildetekst `index'
        local kilde `"`r(tekst)'"'
    }
    restore

    * Indeksverdier for hver årsvariabel
    local j 0
    foreach Y of local years {
        local ++j
        foreach s in kpi lonn g_snitt g_mai {
            tempvar a`j'`s'
            quietly gen double `a`j'`s'' = .
        }
        mata: fafokr__fyll("`Y'", ("`a`j'kpi'", "`a`j'lonn'", "`a`j'g_snitt'", "`a`j'g_mai'"), fafokr__T)
    }
    capture mata: mata drop fafokr__T

    * Selve omregningen
    local nye
    forvalues i = 1/`nvars' {
        local v : word `i' of `varlist'
        local j : list posof "`y`i''" in years
        local s `s`i''
        local d `d`i''
        if "`s'" == "lopende" local nom `v'
        else if "`s'" == "fast" local nom (`v' * `a`j'`d'' / scalar(`B`i''))
        else local nom (`v' * `a`j'`d'')

        tempvar res
        if "`index'" == "nominell" {
            quietly gen double `res' = `nom'
            local ns lopende
            local nb
            local nd
        }
        else if !`gunits' {
            if "`s'" == "fast" & "`d'" == "`index'" {
                quietly gen double `res' = `v' * scalar(`K') / scalar(`B`i'')
            }
            else {
                quietly gen double `res' = `nom' * scalar(`K') / `a`j'`index''
            }
            local ns fast
            local nb `to'
            local nd `index'
        }
        else {
            if "`s'" == "g" & "`d'" == "`index'" {
                quietly gen double `res' = `v'
            }
            else {
                quietly gen double `res' = `nom' / `a`j'`index''
            }
            local ns g
            local nb
            local nd `index'
        }
        quietly count if missing(`res') & !missing(`v')
        local nmiss = r(N)

        if "`replace'" != "" {
            quietly recast double `v'
            quietly replace `v' = `res'
        }
        else {
            quietly gen double `nv`i'' = `res'
            quietly order `nv`i'', after(`v')
        }

        fafokr__beskriv `ns' "`nb'" "`nd'"
        local tekst `"`r(tekst)'"'
        local baselab `"`l`i''"'
        if `"`baselab'"' == "" local baselab `v'
        local nylab = usubstr(`"`baselab', `tekst'"', 1, 80)
        label variable `nv`i'' `"`nylab'"'
        char `nv`i''[fafokr_status] `ns'
        char `nv`i''[fafokr_year] `y`i''
        char `nv`i''[fafokr_base] `nb'
        char `nv`i''[fafokr_deflator] `nd'
        char `nv`i''[fafokr_label] `baselab'
        local nye `nye' `nv`i''

        di as txt "  `v' -> " as res "`nv`i''" as txt ": `tekst'" _c
        if `nmiss' > 0 {
            di as err "  (`nmiss' verdier manglende: indeksen mangler for året)"
        }
        else di ""
    }
    if `"`kilde'"' != "" di as txt "  Kilde: `kilde'"

    return local varlist `nye'
    return local index `index'
    return local to `to'
    return local kilde `"`kilde'"'
    return local dir `"`dir'"'
end

* ---------------------------------------------------------------------------
* fafokr describe: vis status
* ---------------------------------------------------------------------------
program define fafokr_describe, rclass
    syntax [varlist]
    local n 0
    foreach v of local varlist {
        local s : char `v'[fafokr_status]
        if "`s'" != "" {
            local ++n
            if `n' == 1 {
                di as txt _n "{hline 72}"
                di as txt %-24s "Variabel" "Status" _col(60) "År i"
                di as txt "{hline 72}"
            }
            local b : char `v'[fafokr_base]
            local d : char `v'[fafokr_deflator]
            local y : char `v'[fafokr_year]
            fafokr__beskriv `s' "`b'" "`d'"
            di as res %-24s abbrev("`v'", 23) as txt `"`r(tekst)'"' _col(60) as res "`y'"
        }
    }
    if `n' == 0 {
        di as txt "Ingen variabler har fafokr-status. Bruk {cmd:fafokr set}."
    }
    else di as txt "{hline 72}"
    return scalar N = `n'
end

* ---------------------------------------------------------------------------
* fafokr g: lag en variabel med G
* ---------------------------------------------------------------------------
program define fafokr_g, rclass
    syntax varname(numeric), GENerate(name) [Type(string)]
    confirm new variable `generate'
    local type = ustrlower(`"`type'"')
    if "`type'" == "" local type snitt
    if inlist("`type'", "g_snitt", "gjennomsnitt") local type snitt
    if "`type'" == "g_mai" local type mai
    if inlist("`type'", "date", "dag") local type dato
    if !inlist("`type'", "snitt", "mai", "dato") {
        di as err "type() må være snitt, mai eller dato."
        exit 198
    }

    preserve
    if "`type'" == "dato" {
        fafokr__load g
        local dir `"`r(dir)'"'
        tempvar fra
        quietly gen double `fra' = date(fra_dato, "YMD")
        mata: fafokr__P = st_data(., ("`fra'", "g"))
    }
    else {
        fafokr__load aar
        local dir `"`r(dir)'"'
        mata: fafokr__T = st_data(., "aar kpi lonn g_snitt g_mai")
    }
    restore

    quietly gen double `generate' = .
    if "`type'" == "dato" {
        mata: fafokr__gdato("`varlist'", "`generate'", fafokr__P)
        capture mata: mata drop fafokr__P
        label variable `generate' "G gjeldende på dato i `varlist'"
    }
    else {
        tempvar t1 t2 t3 t4
        foreach t in t1 t2 t3 t4 {
            quietly gen double ``t'' = .
        }
        mata: fafokr__fyll("`varlist'", ("`t1'", "`t2'", "`t3'", "`t4'"), fafokr__T)
        capture mata: mata drop fafokr__T
        if "`type'" == "snitt" {
            quietly replace `generate' = `t3'
            label variable `generate' "Gjennomsnittlig G i året (`varlist')"
        }
        else {
            quietly replace `generate' = `t4'
            label variable `generate' "G per 1. mai i året (`varlist')"
        }
    }
    quietly count if missing(`generate') & !missing(`varlist')
    if r(N) > 0 di as txt "(`r(N)' observasjoner utenfor perioden med G fikk manglende verdi)"
    return local dir `"`dir'"'
end

* ---------------------------------------------------------------------------
* fafokr table: last en tabell inn i minnet
* ---------------------------------------------------------------------------
program define fafokr_table, rclass
    syntax [anything(name=tab)] [, CLEAR]
    if `"`tab'"' == "" local tab aar
    local tab = ustrlower(`"`tab'"')
    if "`tab'" == "kpi" local tab kpi_mnd
    if !inlist("`tab'", "aar", "g", "kpi_mnd", "kilder") {
        di as err "Tabellen må være aar, g, kpi_mnd eller kilder."
        exit 198
    }
    if c(changed) & "`clear'" == "" {
        error 4
    }
    fafokr__load `tab'
    local dir `"`r(dir)'"'
    if "`tab'" == "aar" {
        label variable aar "År"
        label variable g_snitt "Gjennomsnittlig G"
        label variable g_mai "G per 1. mai"
        label variable kpi "KPI (2015=100), årsgjennomsnitt"
        label variable lonn "Lønnsindeks (2010=100), påløpt årslønn"
    }
    else if "`tab'" == "g" {
        quietly gen double fra = date(fra_dato, "YMD")
        quietly gen double til = date(til_dato, "YMD")
        format fra til %td
        drop fra_dato til_dato
        order fra til
        label variable fra "Gjelder fra"
        label variable til "Gjelder til"
        label variable g "Grunnbeløpet (G)"
        label variable g_mnd "G per måned"
    }
    else if "`tab'" == "kpi_mnd" {
        quietly gen int ym = ym(aar, mnd)
        format ym %tm
        order ym
        label variable kpi "KPI (2015=100)"
    }
    quietly compress
    di as txt "fafokr: lastet tabellen " as res "`tab'" as txt " fra " as res `"`dir'"'
    return local dir `"`dir'"'
end

* ---------------------------------------------------------------------------
* fafokr sources: vis kilder og hentedatoer
* ---------------------------------------------------------------------------
program define fafokr_sources, rclass
    syntax
    preserve
    fafokr__load kilder
    local dir `"`r(dir)'"'
    di as txt _n "fafokr: datagrunnlag i " as res `"`dir'"'
    forvalues r = 1/`=_N' {
        local s = serie[`r']
        local b = beskrivelse[`r']
        local k = kilde[`r']
        local t = tabell[`r']
        local h = hentet[`r']
        local f = forste_aar[`r']
        local l = siste_aar[`r']
        if "`t'" != "" local k "`k' tabell `t'"
        if "`h'" == "" local h "ikke hentet"
        else local h "hentet `h'"
        if "`f'" != "" local h "`h', `f'–`l'"
        di as res "  " %-6s "`s'" as txt `"`b'"'
        di as txt _col(11) `"`k', `h'"'
    }
    restore
    return local dir `"`dir'"'
end

* ---------------------------------------------------------------------------
* fafokr update: hent nye CSV-filer fra en mappe eller URL
* ---------------------------------------------------------------------------
program define fafokr_update, rclass
    syntax , From(string)
    local from `"`from'"'
    while inlist(usubstr(`"`from'"', -1, 1), "/", "\") {
        local from = usubstr(`"`from'"', 1, ustrlen(`"`from'"') - 1)
    }
    local filer aar g kpi_mnd kilder
    foreach f of local filer {
        tempfile t_`f'
        capture copy `"`from'/fafokr_`f'.csv"' `"`t_`f''"', replace
        if _rc {
            di as err `"Fant ikke `from'/fafokr_`f'.csv"'
            exit 601
        }
    }

    * Kontroller innholdet før noe lagres
    preserve
    quietly import delimited using `"`t_aar'"', clear varnames(1) encoding("utf-8") asdouble
    foreach v in aar g_snitt g_mai kpi lonn {
        capture confirm variable `v'
        if _rc {
            di as err "fafokr_aar.csv mangler variabelen `v'."
            exit 459
        }
    }
    quietly import delimited using `"`t_kilder'"', clear varnames(1) encoding("utf-8") stringcols(_all)
    foreach v in serie kilde hentet {
        capture confirm variable `v'
        if _rc {
            di as err "fafokr_kilder.csv mangler variabelen `v'."
            exit 459
        }
    }
    restore

    * Lagre i PERSONAL-mappen, som Stata leter i før pakkens egen mappe
    local pers = subinstr(`"`c(sysdir_personal)'"', "\", "/", .)
    while usubstr(`"`pers'"', -1, 1) == "/" {
        local pers = usubstr(`"`pers'"', 1, ustrlen(`"`pers'"') - 1)
    }
    local forelder = usubstr(`"`pers'"', 1, ustrrpos(`"`pers'"', "/") - 1)
    capture mkdir `"`forelder'"'
    capture mkdir `"`pers'"'
    mata: st_local("finnes", strofreal(direxists(`"`pers'"')))
    if !`finnes' {
        di as err `"Klarte ikke opprette `pers'."'
        exit 603
    }
    foreach f of local filer {
        copy `"`t_`f''"' `"`pers'/fafokr_`f'.csv"', replace
    }
    di as txt `"fafokr: nye tall lagret i `pers'"'
    fafokr_sources
    return local dir `"`pers'/"'
end

* ---------------------------------------------------------------------------
* Hjelpeprogrammer
* ---------------------------------------------------------------------------

* Finn mappen med nyest datagrunnlag: PERSONAL (fra fafokr update) eller
* mappen pakken ble installert i (PLUS/f/). Ved likt hentetidspunkt vinner
* PERSONAL. Finnes ingen av dem, brukes findfile (f.eks. arbeidsmappen).
program define fafokr__dir, rclass
    local p1 = subinstr(`"`c(sysdir_personal)'"', "\", "/", .)
    local p2 = subinstr(`"`c(sysdir_plus)'f/"', "\", "/", .)
    local valgt ""
    local vdato = -1
    forvalues i = 1/2 {
        capture confirm file `"`p`i''fafokr_kilder.csv"'
        if !_rc {
            fafokr__maxdato `"`p`i''fafokr_kilder.csv"'
            local d = r(maxdato)
            if missing(`d') local d = 0
            if `d' > `vdato' {
                local vdato = `d'
                local valgt `"`p`i''"'
            }
        }
    }
    if `"`valgt'"' == "" {
        capture findfile fafokr_kilder.csv
        if _rc {
            di as err "Fant ikke datagrunnlaget for fafokr (fafokr_kilder.csv)."
            di as err "Installer pakken på nytt, eller bruk {cmd:fafokr update, from()}."
            exit 601
        }
        local fn = subinstr(`"`r(fn)'"', "\", "/", .)
        local valgt = usubstr(`"`fn'"', 1, ustrrpos(`"`fn'"', "/"))
    }
    return local dir `"`valgt'"'
end

program define fafokr__maxdato, rclass
    args fil
    preserve
    quietly import delimited using `"`fil'"', clear varnames(1) encoding("utf-8") stringcols(_all)
    capture confirm variable hentet
    if _rc {
        return scalar maxdato = .
        exit
    }
    tempvar d
    quietly gen double `d' = date(hentet, "YMD")
    quietly summarize `d', meanonly
    return scalar maxdato = r(max)
end

* Leser én av CSV-filene inn i minnet (erstatter data).
program define fafokr__load, rclass
    args fil
    fafokr__dir
    local dir `"`r(dir)'"'
    capture confirm file `"`dir'fafokr_`fil'.csv"'
    if _rc {
        di as err `"Fant ikke `dir'fafokr_`fil'.csv."'
        exit 601
    }
    local sc
    if "`fil'" == "kilder" local sc stringcols(_all)
    if "`fil'" == "g" local sc stringcols(1 2)
    quietly import delimited using `"`dir'fafokr_`fil'.csv"', clear varnames(1) ///
        encoding("utf-8") asdouble `sc'
    if "`fil'" == "aar" {
        foreach s in g_snitt g_mai kpi lonn {
            capture confirm variable `s'
            if _rc quietly gen double `s' = .
            capture confirm numeric variable `s'
            if _rc quietly destring `s', replace force
        }
        sort aar
    }
    return local dir `"`dir'"'
end

* Feiler med en forklaring hvis en serie mangler helt i datagrunnlaget.
program define fafokr__sjekkserie
    args serie
    quietly count if !missing(`serie')
    if r(N) == 0 {
        fafokr__navn `serie'
        di as err "`r(navn)' finnes ikke i datagrunnlaget for fafokr ennå."
        di as err "Hent tallene med {cmd:fafokr update, from()} (eller {cmd:fk_oppdater()} i R)."
        exit 459
    }
end

* Slår opp én verdi i årstabellen (som må ligge i minnet).
program define fafokr__oppslag, rclass
    args serie aar
    quietly summarize `serie' if aar == `aar', meanonly
    if r(N) != 1 {
        fafokr__navn `serie'
        local navn `"`r(navn)'"'
        quietly summarize aar if !missing(`serie'), meanonly
        di as err "`navn' mangler for `aar'. Tilgjengelige år: `r(min)'–`r(max)'."
        exit 459
    }
    return scalar val = r(mean)
end

program define fafokr__navn, rclass
    args serie
    if "`serie'" == "kpi" local n "KPI"
    else if "`serie'" == "lonn" local n "lønnsindeks"
    else if "`serie'" == "g_snitt" local n "gj.snittlig G"
    else if "`serie'" == "g_mai" local n "G per 1. mai"
    else local n "`serie'"
    return local navn `"`n'"'
end

program define fafokr__beskriv, rclass
    args status base deflator
    fafokr__navn `deflator'
    local dn `"`r(navn)'"'
    if "`status'" == "lopende" local t "løpende kroner"
    else if "`status'" == "fast" {
        if inlist("`deflator'", "kpi", "lonn") local t "faste `base'-kroner (`dn')"
        else local t "G-justert til `base'-nivå (`dn')"
    }
    else if "`status'" == "g" local t "G-enheter (`dn')"
    else local t "ukjent status"
    return local tekst `"`t'"'
end

* Kort kildetekst for en indeks, f.eks. "SSB tabell 03013, hentet 2026-10-15".
program define fafokr__kildetekst, rclass
    args index
    local serie `index'
    if inlist("`index'", "g_snitt", "g_mai") local serie g
    fafokr__load kilder
    local tekst
    forvalues r = 1/`=_N' {
        if serie[`r'] == "`serie'" {
            local k = kilde[`r']
            local t = tabell[`r']
            local h = hentet[`r']
            if "`t'" != "" local k "`k' tabell `t'"
            local tekst "`k', hentet `h'"
        }
    }
    return local tekst `"`tekst'"'
end

program define fafokr__normstatus, rclass
    args x
    local x = ustrlower(ustrtrim(`"`x'"'))
    if inlist(`"`x'"', "løpende", "lopende", "nominell", "nominal", "lop") local x lopende
    else if inlist(`"`x'"', "fast", "faste", "real", "deflatert") local x fast
    else if inlist(`"`x'"', "g", "g-enheter", "genheter", "g_enheter") local x g
    return local status `"`x'"'
end

program define fafokr__normindex, rclass
    args x
    local x = ustrlower(ustrtrim(`"`x'"'))
    if inlist(`"`x'"', "kpi", "cpi") local x kpi
    else if inlist(`"`x'"', "lonn", "lønn", "lonnsindeks", "lønnsindeks", "wage", "arslonn", "årslønn") local x lonn
    else if inlist(`"`x'"', "g", "g_snitt", "snitt", "gsnitt") local x g_snitt
    else if inlist(`"`x'"', "g_mai", "mai", "gmai") local x g_mai
    else if inlist(`"`x'"', "nominell", "lopende", "løpende", "nominal") local x nominell
    return local index `"`x'"'
end

* ---------------------------------------------------------------------------
* Mata
* ---------------------------------------------------------------------------
version 14
mata:

// Fyller variablene i tvars med kolonne 2, 3, ... i T (kolonne 1 = år)
// for årstallet i yvar. Årene i T må være sammenhengende.
void fafokr__fyll(string scalar yvar, string rowvector tvars, real matrix T)
{
    real colvector y, i, ok, ut
    real scalar a0, n, k

    a0 = T[1, 1]
    n = rows(T)
    if (T[., 1] != (a0::(a0 + n - 1))) {
        _error("fafokr: årstabellen har ikke sammenhengende år")
    }
    y = st_data(., yvar)
    i = y :- a0 :+ 1
    ok = selectindex((i :>= 1) :& (i :<= n) :& (y :== floor(y)))
    for (k = 1; k <= cols(tvars); k++) {
        ut = J(rows(y), 1, .)
        if (rows(ok) > 0) ut[ok] = T[i[ok], k + 1]
        st_store(., tvars[k], ut)
    }
}

// G gjeldende på datoene i dvar, gitt perioder P = (fra-dato, G).
void fafokr__gdato(string scalar dvar, string scalar gvar, real matrix P)
{
    real colvector d, ut, idx
    real scalar p

    P = sort(P, 1)
    d = st_data(., dvar)
    ut = J(rows(d), 1, .)
    for (p = 1; p <= rows(P); p++) {
        idx = selectindex((d :>= P[p, 1]) :& (d :< .))
        if (rows(idx) > 0) ut[idx] = J(rows(idx), 1, P[p, 2])
    }
    st_store(., gvar, ut)
}

end
