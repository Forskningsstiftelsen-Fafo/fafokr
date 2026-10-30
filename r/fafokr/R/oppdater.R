#' Hent nye tall for G, KPI, lønnsindeks og valutakurser
#'
#' Henter grunnbeløpet fra Navs G-API (g.nav.no), KPI (tabell 14700, med
#' tabell 14710 for månedene før 2000) og
#' en lønnsindeks (2025=100, beregnet fra påløpt årslønn for alle lønnstakere
#' i tabell 14858) fra SSBs
#' statistikkbank via PxWebApi v2, og årsgjennomsnittet av valutakursene for
#' USD og EUR fra Norges Banks åpne API. Tallene kontrolleres før de lagres.
#'
#' Hvis én serie ikke kan hentes, beholdes de forrige tallene for den serien,
#' og funksjonen gir en advarsel. De andre seriene oppdateres likevel.
#'
#' Filene lagres i en lokal cache (se [fk_cache_mappe()]) som pakken bruker
#' når den er nyere enn det innebygde øyeblikksbildet. Med `mappe` kan du i
#' tillegg skrive filene til andre mapper, for eksempel en delt mappe som
#' Stata-brukere henter fra med `fafokr update, from()`.
#'
#' @param mappe Ekstra mapper filene skal skrives til (valgfritt).
#' @param cache Skal filene lagres i den lokale cachen? Standard `TRUE`.
#' @param serier Hvilke serier som skal hentes: `"g"`, `"kpi"`, `"lonn"` og/eller
#'   `"valuta"` (USD og EUR).
#' @param forrige Mappe med forrige versjon av filene. Standard er
#'   datagrunnlaget pakken bruker nå.
#' @param g_kilde URL eller lokal fil med G i API-formatet (valgfritt; brukes
#'   for testing og når g.nav.no ikke er tilgjengelig).
#' @return Kildetabellen (usynlig).
#' @examples
#' \dontrun{
#' fk_oppdater()
#' fk_oppdater(mappe = "K:/Felles/fafokr")   # også til en delt mappe for Stata
#' }
#' @export
fk_oppdater <- function(mappe = NULL, cache = TRUE, serier = c("g", "kpi", "lonn", "valuta"),
                        forrige = NULL, g_kilde = NULL) {
  serier <- match.arg(serier, several.ok = TRUE)
  gammel <- if (!is.null(forrige)) .fk_les_mappe(forrige) else
    tryCatch(.fk_data(), error = function(e) NULL)
  idag <- format(Sys.Date())

  kilder <- if (!is.null(gammel)) gammel$kilder else .fk_tom_kilder()
  g_perioder <- gammel$g
  g_aar <- if (!is.null(gammel)) gammel$aar[, c("aar", "g_snitt", "g_mai")] else NULL
  kpi_mnd <- gammel$kpi_mnd %||% data.frame(aar = integer(), mnd = integer(), kpi = numeric())
  kpi_aar <- if (!is.null(gammel)) gammel$aar[!is.na(gammel$aar$kpi), c("aar", "kpi")] else NULL
  lonn_aar <- if (!is.null(gammel)) gammel$aar[!is.na(gammel$aar$lonn), c("aar", "lonn")] else NULL
  usd_aar <- if (!is.null(gammel)) gammel$aar[!is.na(gammel$aar$usd), c("aar", "usd")] else NULL
  eur_aar <- if (!is.null(gammel)) gammel$aar[!is.na(gammel$aar$eur), c("aar", "eur")] else NULL

  prov <- function(navn, uttrykk) {
    tryCatch(uttrykk, error = function(e) {
      warning("Kunne ikke oppdatere ", navn, ": ", conditionMessage(e),
              "\nDe forrige tallene beholdes.", call. = FALSE)
      NULL
    })
  }

  if ("g" %in% serier) {
    message("Henter grunnbel\u00f8pet fra Nav ...")
    g <- prov("G", .fk_hent_g(g_kilde))
    if (!is.null(g)) {
      g_perioder <- g$perioder
      g_aar <- g$aar
      kilder <- .fk_sett_kilde(kilder, "g", g$url, NA, idag, range(g$aar$aar))
    }
  }
  if ("kpi" %in% serier) {
    message("Henter KPI fra SSB (tabell 14700 og 14710) ...")
    k <- prov("KPI", .fk_hent_kpi())
    if (!is.null(k)) {
      kpi_mnd <- k$mnd
      kpi_aar <- k$aar
      kilder <- .fk_sett_kilde(kilder, "kpi", k$url, k$tabell, idag, range(k$aar$aar))
    }
  }
  if ("lonn" %in% serier) {
    message("Henter \u00e5rsl\u00f8nn fra SSB (tabell 14858) ...")
    l <- prov("l\u00f8nnsindeksen", .fk_hent_lonn())
    if (!is.null(l)) {
      lonn_aar <- l$aar
      kilder <- .fk_sett_kilde(kilder, "lonn", l$url, l$tabell, idag, range(l$aar$aar))
    }
  }

  if ("valuta" %in% serier) {
    message("Henter valutakurser fra Norges Bank ...")
    v <- prov("valutakursene", .fk_hent_valuta())
    if (!is.null(v)) {
      usd_aar <- v$usd
      eur_aar <- v$eur
      kilder <- .fk_sett_kilde(kilder, "usd", v$url, "EXR", idag, range(v$usd$aar))
      kilder <- .fk_sett_kilde(kilder, "eur", v$url, "EXR", idag, range(v$eur$aar))
    }
  }

  if (is.null(g_aar)) stop("Mangler G, og kunne ikke hente det.", call. = FALSE)
  aar <- .fk_slaa_sammen(g_aar, kpi_aar, lonn_aar, usd_aar, eur_aar)
  .fk_valider(aar, g_perioder)

  data <- list(aar = aar, g = g_perioder, kpi_mnd = kpi_mnd, kilder = kilder)
  mapper <- c(if (cache) fk_cache_mappe(), mappe)
  if (!length(mapper)) warning("Ingen mappe \u00e5 skrive til (cache = FALSE og mappe = NULL).", call. = FALSE)
  for (m in mapper) .fk_skriv(data, m)

  .fk_nullstill()
  if (cache) fk_kilder()
  invisible(kilder)
}

.fk_tom_kilder <- function() {
  data.frame(
    serie = c("g", "kpi", "lonn", "usd", "eur"),
    beskrivelse = c(
      "Grunnbel\u00f8pet i folketrygden (G), per 1. mai og gjennomsnitt per \u00e5r",
      "Konsumprisindeksen (2025=100), \u00e5rsgjennomsnitt av m\u00e5nedstall",
      "\u00c5rsl\u00f8nn, p\u00e5l\u00f8pt, alle l\u00f8nnstakere, indeks (2025=100) beregnet fra kroner",
      "Valutakurs, NOK per USD, \u00e5rsgjennomsnitt",
      "Valutakurs, NOK per EUR, \u00e5rsgjennomsnitt"
    ),
    kilde = c("Nav, g.nav.no", "SSB", "SSB", "Norges Bank", "Norges Bank"),
    tabell = c(NA, "14700 (f\u00f8r 2000: 14710)", "14858", "EXR", "EXR"),
    url = NA_character_,
    basis = c("kroner", "2025=100", "2025=100", "NOK per USD", "NOK per EUR"),
    hentet = NA_character_,
    forste_aar = NA_integer_,
    siste_aar = NA_integer_,
    stringsAsFactors = FALSE
  )
}

.fk_sett_kilde <- function(kilder, serie, url, tabell, hentet, spenn) {
  i <- match(serie, kilder$serie)
  if (is.na(i)) {
    kilder <- rbind(kilder, .fk_tom_kilder()[.fk_tom_kilder()$serie == serie, ])
    i <- nrow(kilder)
  }
  mal <- .fk_tom_kilder()
  j <- match(serie, mal$serie)
  kilder$beskrivelse[i] <- mal$beskrivelse[j]
  kilder$kilde[i] <- mal$kilde[j]
  kilder$basis[i] <- mal$basis[j]
  kilder$url[i] <- url
  if (!is.na(tabell)) kilder$tabell[i] <- tabell
  kilder$hentet[i] <- hentet
  kilder$forste_aar[i] <- spenn[1]
  kilder$siste_aar[i] <- spenn[2]
  kilder
}

# Slår sammen årsseriene til én tabell med sammenhengende år.
.fk_slaa_sammen <- function(g_aar, kpi_aar, lonn_aar, usd_aar = NULL, eur_aar = NULL) {
  alle <- c(g_aar$aar, kpi_aar$aar, lonn_aar$aar, usd_aar$aar, eur_aar$aar)
  aar <- data.frame(aar = seq(min(alle), max(alle)))
  aar$g_snitt <- g_aar$g_snitt[match(aar$aar, g_aar$aar)]
  aar$g_mai <- g_aar$g_mai[match(aar$aar, g_aar$aar)]
  aar$kpi <- if (is.null(kpi_aar)) NA_real_ else kpi_aar$kpi[match(aar$aar, kpi_aar$aar)]
  aar$lonn <- if (is.null(lonn_aar)) NA_real_ else lonn_aar$lonn[match(aar$aar, lonn_aar$aar)]
  aar$usd <- if (is.null(usd_aar)) NA_real_ else usd_aar$usd[match(aar$aar, usd_aar$aar)]
  aar$eur <- if (is.null(eur_aar)) NA_real_ else eur_aar$eur[match(aar$aar, eur_aar$aar)]
  aar
}

.fk_valider <- function(aar, g) {
  if (anyDuplicated(aar$aar) || any(diff(aar$aar) != 1)) {
    stop("\u00c5rstabellen har ikke sammenhengende \u00e5r.", call. = FALSE)
  }
  for (s in c(.fk_indekser, .fk_valutaer)) {
    v <- aar[[s]]
    if (any(!is.na(v) & v <= 0)) stop("Serien ", s, " har verdier som ikke er positive.", call. = FALSE)
  }
  ok <- !is.na(aar$g_snitt)
  if (any(diff(aar$g_snitt[ok]) <= 0)) stop("Gjennomsnittlig G er ikke stigende.", call. = FALSE)
  if (is.null(g) || !nrow(g)) stop("Mangler periodetabellen for G.", call. = FALSE)
  invisible(TRUE)
}

.fk_skriv <- function(data, mappe) {
  dir.create(mappe, recursive = TRUE, showWarnings = FALSE)
  for (navn in names(.fk_filer)) {
    sti <- file.path(mappe, .fk_filer[[navn]])
    tmp <- paste0(sti, ".tmp")
    utils::write.csv(data[[navn]], tmp, row.names = FALSE, na = "", fileEncoding = "UTF-8")
    if (!file.rename(tmp, sti)) {
      file.copy(tmp, sti, overwrite = TRUE)
      unlink(tmp)
    }
  }
  invisible(mappe)
}
