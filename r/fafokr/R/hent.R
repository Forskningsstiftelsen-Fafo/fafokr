# Henting av G fra Nav og KPI/lønnsindeks fra SSB.

.fk_url_g <- c(
  # Navs G-API. Historikk-endepunktet returnerer alle grunnbeløp siden 1967.
  "https://g.nav.no/api/v1/historikk/grunnbel%C3%B8p",
  # Reserve: datafilen API-et leser fra, i Navs åpne kildekode.
  "https://raw.githubusercontent.com/navikt/g/main/grunnbel%C3%B8p.json"
)
.fk_url_ssb <- "https://data.ssb.no/api/pxwebapi/v2/tables"

# Leser tekst fra en URL eller lokal fil, med nye forsøk ved feil (f.eks. 429).
.fk_les_tekst <- function(kilde, forsok = 3) {
  if (file.exists(kilde)) {
    return(paste(readLines(kilde, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  }
  siste_feil <- NULL
  for (i in seq_len(forsok)) {
    res <- tryCatch({
      con <- url(kilde, encoding = "UTF-8")
      tekst <- tryCatch(readLines(con, warn = FALSE, encoding = "UTF-8"),
                        finally = close(con))
      paste(tekst, collapse = "\n")
    }, error = function(e) e, warning = function(w) w)
    if (is.character(res)) return(res)
    siste_feil <- conditionMessage(res)
    if (i < forsok) Sys.sleep(2^i)
  }
  stop("Klarte ikke hente ", kilde, ": ", siste_feil, call. = FALSE)
}

# ---- Grunnbeløpet ----------------------------------------------------------

# Gjør JSON fra G-API-et om til en data.frame med én rad per endring.
.fk_g_fra_json <- function(tekst) {
  rader <- jsonlite::fromJSON(tekst, simplifyVector = FALSE)
  if (!is.null(names(rader))) rader <- list(rader)   # ett enkelt objekt
  if (!length(rader)) stop("Tomt svar fra G-API-et.", call. = FALSE)
  felt <- function(r, navn) {
    i <- match(navn, .fk_ascii(names(r)))
    if (is.na(i) || is.null(r[[i]])) NA else r[[i]]
  }
  ut <- data.frame(
    dato        = as.Date(vapply(rader, function(r) as.character(felt(r, "dato")), "")),
    g           = vapply(rader, function(r) as.numeric(felt(r, "grunnbelop")), 0),
    g_mnd       = vapply(rader, function(r) as.numeric(felt(r, "grunnbeloppermaned")), 0),
    g_snitt_nav = vapply(rader, function(r) as.numeric(felt(r, "gjennomsnittperar")), 0)
  )
  ut <- ut[order(ut$dato), , drop = FALSE]
  if (anyNA(ut$dato) || anyNA(ut$g)) stop("G-API-et ga rader uten dato eller bel\u00f8p.", call. = FALSE)
  if (anyDuplicated(ut$dato)) stop("G-API-et ga samme dato flere ganger.", call. = FALSE)
  if (any(ut$g <= 0) || any(diff(ut$g) <= 0)) {
    stop("Uventede G-verdier (ikke positive eller ikke stigende).", call. = FALSE)
  }
  rownames(ut) <- NULL
  ut
}

# G gjeldende på gitte datoer, gitt en periodetabell sortert etter dato.
.fk_g_paa <- function(datoer, perioder) {
  i <- findInterval(as.numeric(as.Date(datoer)), as.numeric(perioder$dato))
  ut <- rep(NA_real_, length(i))
  ut[i > 0] <- perioder$g[i[i > 0]]
  ut
}

# Lager periodetabellen og årstabellen for G.
.fk_g_tabeller <- function(g) {
  perioder <- data.frame(
    fra_dato = format(g$dato),
    til_dato = c(format(g$dato[-1] - 1), NA),
    g        = g$g,
    g_mnd    = g$g_mnd
  )
  aar <- seq(as.integer(format(min(g$dato), "%Y")), as.integer(format(max(g$dato), "%Y")))
  g_mai <- .fk_g_paa(as.Date(paste0(aar, "-05-01")), g)
  # Navs gjennomsnitt per år = snittet av G gjeldende den 1. i hver måned.
  beregnet <- vapply(aar, function(a) {
    mean(.fk_g_paa(as.Date(sprintf("%d-%02d-01", a, 1:12)), g))
  }, 0)
  g_aar <- as.integer(format(g$dato, "%Y"))
  nav <- vapply(aar, function(a) {
    v <- g$g_snitt_nav[g_aar == a & !is.na(g$g_snitt_nav)]
    if (length(v)) v[length(v)] else NA_real_
  }, 0)
  avvik <- !is.na(nav) & abs(nav - beregnet) > 1.5
  if (any(avvik)) {
    warning("Navs gjennomsnittlige G avviker fra egen beregning for ",
            paste(aar[avvik], collapse = ", "), ". Navs tall brukes.", call. = FALSE)
  }
  g_snitt <- ifelse(is.na(nav), round(beregnet), nav)
  list(
    perioder = perioder,
    aar = data.frame(aar = aar, g_snitt = g_snitt, g_mai = g_mai)
  )
}

.fk_hent_g <- function(kilde = NULL) {
  kilder <- kilde %||% .fk_url_g
  feil <- character()
  for (k in kilder) {
    res <- tryCatch(.fk_g_fra_json(.fk_les_tekst(k)), error = function(e) e)
    if (is.data.frame(res)) {
      tab <- .fk_g_tabeller(res)
      # En lokal kopi av Navs datafil oppgis med sin offisielle adresse.
      tab$url <- if (file.exists(k)) .fk_url_g[2] else k
      return(tab)
    }
    feil <- c(feil, paste0(k, ": ", conditionMessage(res)))
  }
  stop("Klarte ikke hente G.\n", paste(feil, collapse = "\n"), call. = FALSE)
}

# ---- SSB, PxWebApi v2 -------------------------------------------------------

# Leser JSON-stat2 og gir en lang data.frame med én kolonne per dimensjon
# (koder), etiketter i attributtet "etiketter" og verdien i kolonnen "verdi".
.fk_jsonstat <- function(tekst, med_verdier = TRUE) {
  js <- jsonlite::fromJSON(tekst, simplifyVector = FALSE)
  ider <- unlist(js$id)
  if (is.null(ider)) stop("Svaret fra SSB er ikke JSON-stat2.", call. = FALSE)
  koder <- lapply(ider, function(d) {
    kat <- js$dimension[[d]]$category
    idx <- kat$index
    if (is.null(idx)) return(names(kat$label))
    if (!is.null(names(idx))) return(names(idx)[order(unlist(idx))])
    unlist(idx)
  })
  names(koder) <- ider
  etiketter <- lapply(ider, function(d) {
    lab <- js$dimension[[d]]$category$label
    k <- koder[[d]]
    if (is.null(lab)) return(stats::setNames(k, k))
    stats::setNames(vapply(k, function(x) as.character(lab[[x]] %||% x), ""), k)
  })
  names(etiketter) <- ider
  if (!med_verdier) return(list(koder = koder, etiketter = etiketter))

  # JSON-stat er radvis: siste dimensjon varierer raskest.
  grid <- expand.grid(rev(koder), KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  grid <- grid[rev(names(grid))]
  n <- prod(lengths(koder))
  v <- js$value
  if (!is.null(names(v))) {              # glissen form: {"0": 1.2, ...}
    verdi <- rep(NA_real_, n)
    verdi[as.integer(names(v)) + 1L] <- vapply(v, function(z) if (is.null(z)) NA_real_ else as.numeric(z), 0)
  } else {
    verdi <- vapply(v, function(z) if (is.null(z)) NA_real_ else as.numeric(z), 0)
  }
  if (length(verdi) != n) stop("Feil antall verdier i svaret fra SSB.", call. = FALSE)
  grid$verdi <- verdi
  attr(grid, "etiketter") <- etiketter
  grid
}

.fk_ssb_meta <- function(tabell, lang = "en") {
  u <- sprintf("%s/%s/metadata?lang=%s&outputFormat=json-stat2", .fk_url_ssb, tabell, lang)
  .fk_jsonstat(.fk_les_tekst(u), med_verdier = FALSE)
}

.fk_ssb_data_url <- function(tabell, valg, lang = "en") {
  q <- paste0("valueCodes[", names(valg), "]=", unlist(valg), collapse = "&")
  sprintf("%s/%s/data?lang=%s&outputFormat=json-stat2&%s", .fk_url_ssb, tabell, lang, q)
}


# Velger KPI-totalindeksen (indeksnivå, ikke endringer eller vekter) i en
# SSB-tabell ut fra metadataene, og henter alle månedene.
.fk_ssb_kpi_mnd <- function(tab) {
  meta <- .fk_ssb_meta(tab)
  dims <- names(meta$koder)
  if (!all(c("ContentsCode", "Tid") %in% dims)) {
    stop("Tabell ", tab, " har ikke dimensjonene ContentsCode og Tid.", call. = FALSE)
  }
  lab <- tolower(meta$etiketter$ContentsCode)
  treff <- grepl("index|indeks", lab) & !grepl("change|rate|weight|endring|vekt", lab)
  if (sum(treff) > 1) treff <- treff & grepl("2025=100", lab, fixed = TRUE)
  if (sum(treff) != 1) {
    stop("Fant ikke \u00e9n entydig indeks i tabell ", tab, ". Etiketter: ",
         paste(meta$etiketter$ContentsCode, collapse = " | "), call. = FALSE)
  }
  valg <- list()
  for (d in setdiff(dims, c("ContentsCode", "Tid"))) {
    k <- meta$koder[[d]]
    l <- tolower(meta$etiketter[[d]])
    kode <- if (length(k) == 1) k else
      k[k %in% c("00", "TOTAL", "0")][1]
    if (is.na(kode)) kode <- k[grepl("^(00 )?total|all-item|i alt", l)][1]
    if (is.na(kode)) {
      stop("Fant ikke totalindeksen i dimensjonen ", d, " i tabell ", tab, ".", call. = FALSE)
    }
    valg[[d]] <- kode
  }
  valg$ContentsCode <- meta$koder$ContentsCode[treff]
  valg$Tid <- "*"
  u <- .fk_ssb_data_url(tab, valg)
  d <- .fk_jsonstat(.fk_les_tekst(u))
  d <- d[!is.na(d$verdi) & grepl("^[0-9]{4}M[0-9]{2}$", d$Tid), , drop = FALSE]
  if (!nrow(d)) stop("Ingen m\u00e5nedstall for KPI i tabell ", tab, ".", call. = FALSE)
  if (any(d$verdi <= 0)) stop("KPI i tabell ", tab, " har verdier som ikke er positive.", call. = FALSE)
  mnd <- data.frame(aar = as.integer(substr(d$Tid, 1, 4)),
                    mnd = as.integer(substr(d$Tid, 6, 7)), kpi = d$verdi)
  list(mnd = mnd[order(mnd$aar, mnd$mnd), , drop = FALSE], url = u)
}

# KPI (2025=100) fra tabell 14700, som starter i 2000. Månedene før 2000
# hentes fra den historiske serien i tabell 14710 og skjøtes på ved hjelp av
# overlappet i år 2000, slik at hele serien er på samme nivå som 14700.
.fk_hent_kpi <- function() {
  ny <- .fk_ssb_kpi_mnd("14700")
  hist <- .fk_ssb_kpi_mnd("14710")
  nm <- ny$mnd
  hm <- hist$mnd
  forste <- min(nm$aar)
  nokkel <- function(d) d$aar * 100L + d$mnd
  overlapp <- intersect(nokkel(nm[nm$aar == forste, ]), nokkel(hm))
  if (length(overlapp) < 12) {
    stop("For lite overlapp mellom tabell 14700 og 14710 i ", forste, ".", call. = FALSE)
  }
  faktor <- mean(nm$kpi[match(overlapp, nokkel(nm))]) /
            mean(hm$kpi[match(overlapp, nokkel(hm))])
  # Begge tabellene har 2025=100, så faktoren skal være nær 1.
  if (abs(faktor - 1) > 0.05) {
    stop("Tabell 14700 og 14710 passer ikke sammen (faktor ", round(faktor, 4), ").",
         call. = FALSE)
  }
  tidlig <- hm[nokkel(hm) < min(nokkel(nm)), , drop = FALSE]
  tidlig$kpi <- tidlig$kpi * faktor
  mnd <- rbind(tidlig, nm)
  rownames(mnd) <- NULL
  # Årsgjennomsnitt bare for hele år.
  antall <- tapply(mnd$kpi, mnd$aar, length)
  snitt <- tapply(mnd$kpi, mnd$aar, mean)
  hele <- names(antall)[antall == 12]
  aar <- data.frame(aar = as.integer(hele), kpi = round(as.numeric(snitt[hele]), 4))
  list(mnd = data.frame(aar = mnd$aar, mnd = mnd$mnd, kpi = round(mnd$kpi, 4)),
       aar = aar, url = paste(ny$url, hist$url, sep = " ; "),
       tabell = "14700 (f\u00f8r 2000: 14710)", faktor = faktor)
}

# Lønnsindeks (2025=100) konstruert fra gjennomsnittlig påløpt årslønn i
# kroner for alle lønnstakere i tabell 14858. Tabellen har ikke en
# indeksserie, så indeksen er årslønnen i året delt på årslønnen i 2025.
.fk_lonn_basisaar <- 2025L

.fk_hent_lonn <- function() {
  tab <- "14858"
  meta <- .fk_ssb_meta(tab)
  if (!all(c("ContentsCode", "Tid") %in% names(meta$koder))) {
    stop("Tabell ", tab, " har ikke dimensjonene ContentsCode og Tid.", call. = FALSE)
  }
  # Nominell årslønn i kroner: ikke endringstall, ikke realverdier.
  lab <- tolower(meta$etiketter$ContentsCode)
  treff <- grepl("annual earnings", lab) &
    !grepl("real|change|per cent|percent|index|price|constant|fixed", lab)
  if (sum(treff) > 1) treff <- treff & grepl("(nok)", lab, fixed = TRUE)
  if (sum(treff) != 1) {
    stop("Fant ikke \u00e9n entydig serie for nominell \u00e5rsl\u00f8nn i tabell ", tab,
         ". Etiketter: ", paste(meta$etiketter$ContentsCode, collapse = " | "), call. = FALSE)
  }
  valg <- list()
  for (d in setdiff(names(meta$koder), c("ContentsCode", "Tid"))) {
    valg[[d]] <- .fk_totalkode(meta, d, tab)
  }
  valg$ContentsCode <- meta$koder$ContentsCode[treff]
  valg$Tid <- "*"
  u <- .fk_ssb_data_url(tab, valg)
  d <- .fk_jsonstat(.fk_les_tekst(u))
  d <- d[!is.na(d$verdi) & grepl("^[0-9]{4}$", d$Tid), , drop = FALSE]
  if (!nrow(d)) stop("Ingen tall for \u00e5rsl\u00f8nn i tabell ", tab, ".", call. = FALSE)
  kr <- data.frame(aar = as.integer(d$Tid), arslonn = d$verdi)
  kr <- kr[order(kr$aar), , drop = FALSE]
  if (any(kr$arslonn <= 0)) stop("\u00c5rsl\u00f8nnen har verdier som ikke er positive.", call. = FALSE)
  basis <- kr$arslonn[kr$aar == .fk_lonn_basisaar]
  if (length(basis) != 1) {
    stop("Tabell ", tab, " mangler \u00e5rsl\u00f8nn for basis\u00e5ret ", .fk_lonn_basisaar, ".",
         call. = FALSE)
  }
  aar <- data.frame(aar = kr$aar, lonn = round(kr$arslonn / basis * 100, 6))
  rownames(aar) <- NULL
  list(aar = aar, url = u, tabell = tab)
}

# Kode for "alle"/"i alt" i en dimensjon med flere verdier (én verdi tas som den er).
.fk_totalkode <- function(meta, d, tab) {
  k <- meta$koder[[d]]
  if (length(k) == 1) return(k)
  l <- tolower(meta$etiketter[[d]])
  kode <- k[k %in% c("00", "0", "TOTAL", "Total", "Alle", "ALLE")][1]
  if (is.na(kode)) kode <- k[grepl("^(00 )?total|^all|i alt|^alle", l)][1]
  if (is.na(kode)) {
    stop("Fant ikke totalen i dimensjonen ", d, " i tabell ", tab, ".", call. = FALSE)
  }
  kode
}

# ---- Valutakurser fra Norges Bank -------------------------------------------

# Årsgjennomsnitt av daglige kurser (NOK per enhet) for USD og EUR.
.fk_url_nb <- "https://data.norges-bank.no/api/data/EXR/A.USD+EUR.NOK.SP?format=csv&locale=en"

# Leser CSV fra Norges Banks API. Tåler byte order mark, semikolon eller komma
# som skilletegn og desimalkomma (locale=no). Kurser for valutaer som noteres
# per 100 enheter (UNIT_MULT = 2) regnes om til kurs per enhet.
.fk_nb_csv <- function(tekst) {
  tekst <- sub("^\ufeff", "", tekst)
  linjer <- strsplit(tekst, "\r?\n")[[1]]
  linjer <- linjer[nzchar(trimws(linjer))]
  if (length(linjer) < 2) stop("Tomt svar fra Norges Bank.", call. = FALSE)
  sep <- if (grepl(";", linjer[1], fixed = TRUE)) ";" else ","
  d <- utils::read.table(text = linjer, sep = sep, header = TRUE, quote = "\"",
                         colClasses = "character", check.names = FALSE,
                         comment.char = "", stringsAsFactors = FALSE)
  mangler <- setdiff(c("BASE_CUR", "TIME_PERIOD", "OBS_VALUE"), names(d))
  if (length(mangler)) {
    stop("Svaret fra Norges Bank mangler kolonnene ", paste(mangler, collapse = ", "),
         ".", call. = FALSE)
  }
  kurs <- suppressWarnings(as.numeric(sub(",", ".", d$OBS_VALUE, fixed = TRUE)))
  mult <- if ("UNIT_MULT" %in% names(d)) suppressWarnings(as.numeric(d$UNIT_MULT)) else 0
  mult[is.na(mult)] <- 0
  data.frame(valuta = tolower(d$BASE_CUR), periode = d$TIME_PERIOD,
             kurs = kurs / 10^mult, stringsAsFactors = FALSE)
}

.fk_hent_valuta <- function() {
  d <- .fk_nb_csv(.fk_les_tekst(.fk_url_nb))
  d <- d[grepl("^[0-9]{4}$", d$periode) & !is.na(d$kurs), , drop = FALSE]
  d$aar <- as.integer(d$periode)
  # Bare hele år: et årsgjennomsnitt for inneværende år er ikke ferdig.
  d <- d[d$aar < as.integer(format(Sys.Date(), "%Y")), , drop = FALSE]
  if (any(d$kurs <= 0)) stop("Valutakursene har verdier som ikke er positive.", call. = FALSE)
  ut <- list(url = .fk_url_nb)
  for (v in .fk_valutaer) {
    dv <- d[d$valuta == v, , drop = FALSE]
    if (!nrow(dv)) stop("Fant ikke ", toupper(v), " i svaret fra Norges Bank.", call. = FALSE)
    if (anyDuplicated(dv$aar)) stop("Flere kurser for samme \u00e5r (", toupper(v), ").", call. = FALSE)
    dv <- dv[order(dv$aar), , drop = FALSE]
    ut[[v]] <- stats::setNames(data.frame(dv$aar, dv$kurs), c("aar", v))
  }
  ut
}
