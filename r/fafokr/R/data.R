# Innlasting av datagrunnlaget.
#
# Pakken har to mulige kilder:
#   1. det innebygde øyeblikksbildet i inst/extdata (følger med installasjonen)
#   2. en lokal cache som fk_oppdater() skriver til
# Den som har nyest hentedato i fafokr_kilder.csv, brukes.

.fk_env <- new.env(parent = emptyenv())

#' Mappen der fk_oppdater() lagrer nye tall
#'
#' @return Stien til cache-mappen (finnes ikke nødvendigvis).
#' @export
fk_cache_mappe <- function() {
  tools::R_user_dir("fafokr", which = "cache")
}

.fk_les_csv <- function(sti) {
  utils::read.csv(sti, stringsAsFactors = FALSE, fileEncoding = "UTF-8",
                  na.strings = c("", "NA"))
}

# Leser alle fire filene fra en mappe. Returnerer NULL hvis noe mangler.
.fk_les_mappe <- function(mappe) {
  if (is.null(mappe) || !nzchar(mappe)) return(NULL)
  stier <- stats::setNames(file.path(mappe, .fk_filer), names(.fk_filer))
  if (!all(file.exists(stier))) return(NULL)
  ut <- lapply(stier, .fk_les_csv)
  names(ut) <- names(.fk_filer)
  # Kildetabellen leses som tekst, slik at tabellnummer som "09786" beholdes.
  k <- utils::read.csv(stier[["kilder"]], stringsAsFactors = FALSE, fileEncoding = "UTF-8",
                       colClasses = "character", na.strings = c("", "NA"))
  k$forste_aar <- as.integer(k$forste_aar)
  k$siste_aar <- as.integer(k$siste_aar)
  ut$kilder <- k
  for (s in c(.fk_indekser, .fk_valutaer)) {
    ut$aar[[s]] <- if (is.null(ut$aar[[s]])) NA_real_ else as.numeric(ut$aar[[s]])
  }
  ut$kpi_mnd$kpi <- as.numeric(ut$kpi_mnd$kpi)
  ut$g$fra_dato <- as.character(ut$g$fra_dato)
  ut$g$til_dato <- as.character(ut$g$til_dato)
  ut$mappe <- normalizePath(mappe, winslash = "/", mustWork = FALSE)
  ut
}

# Seneste hentedato i et datasett (eller -Inf hvis ingen).
.fk_nyeste <- function(d) {
  if (is.null(d)) return(-Inf)
  datoer <- as.Date(d$kilder$hentet)
  if (all(is.na(datoer))) return(-Inf)
  as.numeric(max(datoer, na.rm = TRUE))
}

.fk_data <- function() {
  if (!is.null(.fk_env$data)) return(.fk_env$data)
  innebygd <- .fk_les_mappe(system.file("extdata", package = "fafokr"))
  cache <- .fk_les_mappe(fk_cache_mappe())
  if (is.null(innebygd) && is.null(cache)) {
    stop("Fant ikke datagrunnlaget for fafokr. Kj\u00f8r fk_oppdater().", call. = FALSE)
  }
  if (!is.null(cache) && .fk_nyeste(cache) >= .fk_nyeste(innebygd)) {
    valgt <- cache
    valgt$type <- "lokal cache"
  } else {
    valgt <- innebygd
    valgt$type <- "innebygd i pakken"
  }
  .fk_env$data <- valgt
  valgt
}

.fk_nullstill <- function() {
  .fk_env$data <- NULL
  invisible(NULL)
}

#' Tabellene i fafokr
#'
#' Gir tabellene pakken regner med.
#'
#' @param tabell \code{"aar"} (én rad per år med \code{g_snitt}, \code{g_mai},
#'   \code{kpi} og \code{lonn}), \code{"g"} (perioder med grunnbeløp),
#'   \code{"kpi_mnd"} (KPI per måned) eller \code{"kilder"}.
#' @return En data.frame.
#' @examples
#' head(fk_tabell("aar"))
#' tail(fk_tabell("g"))
#' @export
fk_tabell <- function(tabell = c("aar", "g", "kpi_mnd", "kilder")) {
  tabell <- match.arg(tabell)
  .fk_data()[[tabell]]
}

#' Kilder og hentedatoer for indeksene
#'
#' Viser hvor tallene kommer fra, når de ble hentet og hvilke år de dekker.
#' Ta med denne informasjonen i metodedelen av rapporter.
#'
#' @return Kildetabellen (usynlig).
#' @export
fk_kilder <- function() {
  d <- .fk_data()
  k <- d$kilder
  cat("fafokr: datagrunnlag ", d$type, "\n", "  (", d$mappe, ")\n\n", sep = "")
  for (i in seq_len(nrow(k))) {
    hentet <- if (is.na(k$hentet[i])) "ikke hentet" else paste("hentet", k$hentet[i])
    dekning <- if (is.na(k$forste_aar[i])) "" else
      paste0(", ", k$forste_aar[i], "\u2013", k$siste_aar[i])
    tab <- if (is.na(k$tabell[i])) "" else paste0(" tabell ", k$tabell[i])
    cat(sprintf("  %-5s %s\n        %s%s, %s%s\n", k$serie[i], k$beskrivelse[i],
                k$kilde[i], tab, hentet, dekning))
  }
  invisible(k)
}

# Kort kildetekst for en indeks, brukt i meldinger.
.fk_kildetekst <- function(indeks) {
  k <- .fk_data()$kilder
  serie <- .fk_serie_for_indeks[[indeks]]
  r <- k[k$serie == serie, , drop = FALSE]
  if (!nrow(r)) return("")
  tab <- if (is.na(r$tabell[1])) "" else paste0(" tabell ", r$tabell[1])
  paste0(r$kilde[1], tab, ", hentet ", r$hentet[1])
}
