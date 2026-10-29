# Status for variabler og omregning mellom løpende kroner, faste kroner og G.
#
# Statusen lagres som attributtet "fafokr" på hver kolonne:
#   list(status = "lopende" | "fast" | "g",
#        aar = navnet på årsvariabelen (eller NA),
#        base = basisår (for "fast"),
#        deflator = indeksen som ble brukt ("fast": kpi, lonn, g_snitt, g_mai;
#                   "g": g_snitt eller g_mai),
#        etikett = opprinnelig etikett)

.fk_lag_status <- function(status, aar = NA_character_, base = NULL, deflator = NULL,
                           etikett = NULL) {
  status <- .fk_norm_status(status)
  deflator <- .fk_norm_indeks(deflator)
  if (status == "lopende") {
    if (!is.null(base) || !is.null(deflator)) {
      stop("base og deflator skal ikke oppgis for l\u00f8pende kroner.", call. = FALSE)
    }
  } else if (status == "fast") {
    if (is.null(base) || is.null(deflator)) {
      stop("Faste kroner krever b\u00e5de base (basis\u00e5r) og deflator ",
           "(kpi, lonn, g_snitt eller g_mai).", call. = FALSE)
    }
    if (!is.numeric(base) || length(base) != 1 || is.na(base)) {
      stop("base m\u00e5 v\u00e6re ett \u00e5rstall.", call. = FALSE)
    }
  } else if (status == "g") {
    if (!is.null(base)) stop("base skal ikke oppgis for G-enheter.", call. = FALSE)
    deflator <- deflator %||% "g_snitt"
    if (!deflator %in% .fk_g_indekser) {
      stop("For G-enheter m\u00e5 deflator v\u00e6re g_snitt eller g_mai.", call. = FALSE)
    }
  }
  list(status = status, aar = aar, base = if (is.null(base)) NULL else as.integer(base),
       deflator = deflator, etikett = etikett)
}

#' Gi en variabel status som løpende kroner, faste kroner eller G-enheter
#'
#' `fk_set()` lagrer statusen på kolonner i en data.frame, slik at
#' [fk_convert()] vet hvordan tallene skal regnes om. `fk_status()` gjør det
#' samme for én vektor.
#'
#' @param data En data.frame.
#' @param cols Kolonnene som skal få status, som tekst eller nakne navn
#'   (`c(inntekt, lonn)`).
#' @param aar Årsvariabelen (tekst eller naket navn). Beløpet i hver rad
#'   gjelder dette året.
#' @param status `"løpende"` (nominelle kroner i året `aar`), `"fast"` (faste
#'   kroner med basisår `base`, deflatert med `deflator`) eller `"g"`
#'   (G-enheter, med `deflator` `"g_snitt"` eller `"g_mai"`).
#' @param base Basisår for faste kroner.
#' @param deflator Indeksen tallene ble deflatert med: `"kpi"`, `"lonn"`,
#'   `"g_snitt"` eller `"g_mai"`.
#' @param replace Overskriv en status som finnes fra før?
#' @return `data` med status på kolonnene.
#' @examples
#' d <- data.frame(aar = 2018:2020, inntekt = c(500000, 520000, 540000),
#'                 pensjon15 = c(200000, 201000, 202000))
#' d <- fk_set(d, inntekt, aar = aar, status = "løpende")
#' d <- fk_set(d, pensjon15, aar = aar, status = "fast", base = 2015, deflator = "g_snitt")
#' fk_info(d)
#' @export
fk_set <- function(data, cols, aar, status, base = NULL, deflator = NULL, replace = FALSE) {
  if (!is.data.frame(data)) stop("data m\u00e5 v\u00e6re en data.frame.", call. = FALSE)
  cols <- .fk_kolonnenavn(substitute(cols), parent.frame())
  aar <- .fk_kolonnenavn(substitute(aar), parent.frame())
  if (length(aar) != 1) stop("Oppgi \u00e9n \u00e5rsvariabel.", call. = FALSE)
  mangler <- setdiff(c(cols, aar), names(data))
  if (length(mangler)) stop("Finner ikke: ", paste(mangler, collapse = ", "), call. = FALSE)
  if (!is.numeric(data[[aar]])) stop("\u00c5rsvariabelen ", aar, " m\u00e5 v\u00e6re numerisk.", call. = FALSE)
  for (v in cols) {
    if (!is.numeric(data[[v]])) stop(v, " er ikke numerisk.", call. = FALSE)
    gml <- attr(data[[v]], "fafokr")
    if (!is.null(gml) && !replace) {
      stop(v, " har allerede status (", .fk_beskriv(gml), "). Bruk replace = TRUE.",
           call. = FALSE)
    }
    etikett <- attr(data[[v]], "label") %||% gml$etikett %||% v
    attr(data[[v]], "fafokr") <- .fk_lag_status(status, aar, base, deflator, etikett)
  }
  data
}

#' @rdname fk_set
#' @param x En numerisk vektor.
#' @export
fk_status <- function(x, status, base = NULL, deflator = NULL) {
  if (!is.numeric(x)) stop("x m\u00e5 v\u00e6re numerisk.", call. = FALSE)
  attr(x, "fafokr") <- .fk_lag_status(status, NA_character_, base, deflator,
                                      attr(x, "label"))
  x
}

#' Vis status for variablene i en data.frame
#'
#' @param data En data.frame.
#' @return En data.frame med én rad per variabel som har status.
#' @export
fk_info <- function(data) {
  rader <- lapply(names(data), function(v) {
    m <- attr(data[[v]], "fafokr")
    if (is.null(m)) return(NULL)
    data.frame(variabel = v, status = m$status, aar = m$aar %||% NA,
               base = m$base %||% NA, deflator = m$deflator %||% NA,
               valuta = m$valuta %||% NA,
               beskrivelse = .fk_beskriv(m), stringsAsFactors = FALSE)
  })
  rader <- do.call(rbind, rader)
  if (is.null(rader)) {
    message("Ingen variabler har fafokr-status. Bruk fk_set().")
    return(invisible(data.frame()))
  }
  rader
}

.fk_beskriv <- function(m) {
  tekst <- .fk_beskriv_nok(m)
  if (is.null(m$valuta)) return(tekst)
  V <- toupper(m$valuta)
  if (m$status == "lopende") return(sprintf("l\u00f8pende %s (\u00e5rets kurs)", V))
  sprintf("%s, i %s (%d-kurs)", tekst, V, m$base)
}

.fk_beskriv_nok <- function(m) {
  switch(m$status,
    lopende = "l\u00f8pende kroner",
    fast = if (m$deflator %in% c("kpi", "lonn")) {
      sprintf("faste %d-kroner (%s)", m$base, .fk_indeksnavn[[m$deflator]])
    } else {
      sprintf("G-justert til %d-niv\u00e5 (%s)", m$base, .fk_indeksnavn[[m$deflator]])
    },
    g = sprintf("G-enheter (%s)", .fk_indeksnavn[[m$deflator]])
  )
}

# ---- Oppslag i indekstabellen -----------------------------------------------

.fk_serie <- function(indeks) {
  tab <- .fk_data()$aar
  v <- tab[[indeks]]
  if (all(is.na(v))) {
    stop(.fk_indeksnavn[[indeks]], " finnes ikke i datagrunnlaget (", .fk_data()$type,
         "). Kj\u00f8r fk_oppdater() for \u00e5 hente tallene.", call. = FALSE)
  }
  tab
}

.fk_I <- function(indeks, aar) {
  tab <- .fk_serie(indeks)
  tab[[indeks]][match(aar, tab$aar)]
}

.fk_I1 <- function(indeks, aar) {
  v <- .fk_I(indeks, aar)
  if (length(v) != 1 || is.na(v)) {
    tab <- .fk_data()$aar
    ok <- tab$aar[!is.na(tab[[indeks]])]
    stop(.fk_indeksnavn[[indeks]], " mangler for ", aar, ". Tilgjengelige \u00e5r: ",
         min(ok), "\u2013", max(ok), ".", call. = FALSE)
  }
  v
}

# Fra hvilken som helst status til løpende kroner.
.fk_nominell <- function(x, aar, m) {
  switch(m$status,
    lopende = x,
    fast = x * .fk_I(m$deflator, aar) / .fk_I1(m$deflator, m$base),
    g = x * .fk_I(m$deflator, aar)
  )
}

# Selve omregningen. Returnerer verdier og ny status.
.fk_kjerne <- function(x, aar, m, index, to) {
  if (index == "nominell") {
    if (!is.null(to)) stop("til/to skal ikke oppgis for l\u00f8pende kroner.", call. = FALSE)
    return(list(x = .fk_nominell(x, aar, m), m = .fk_lag_status("lopende", m$aar)))
  }
  g_enheter <- index %in% .fk_g_indekser && is.null(to)
  if (!g_enheter) {
    if (is.null(to)) stop("Oppgi til hvilket \u00e5r (to) med ", index, ".", call. = FALSE)
    if (!is.numeric(to) || length(to) != 1) stop("to m\u00e5 v\u00e6re ett \u00e5rstall.", call. = FALSE)
    faktor_til <- .fk_I1(index, to)
    ut <- if (m$status == "fast" && m$deflator == index) {
      x * faktor_til / .fk_I1(index, m$base)
    } else {
      .fk_nominell(x, aar, m) * faktor_til / .fk_I(index, aar)
    }
    return(list(x = ut, m = .fk_lag_status("fast", m$aar, to, index)))
  }
  ut <- if (m$status == "g" && m$deflator == index) {
    x
  } else {
    .fk_nominell(x, aar, m) / .fk_I(index, aar)
  }
  list(x = ut, m = .fk_lag_status("g", m$aar, deflator = index))
}

# Regner et NOK-resultat om til valuta. Løpende kroner bruker kursen for
# hvert års beløp; faste kroner (og G-justerte kroner) bruker kursen i
# basisåret, slik at realverdien beholdes.
.fk_til_valuta <- function(res, aar, valuta) {
  if (is.null(valuta)) return(res)
  if (res$m$status == "g") {
    stop("G-enheter kan ikke regnes om til valuta. Bruk kpi, lonn eller nominell, ",
         "eller G-justerte kroner (g_snitt/g_mai med to).", call. = FALSE)
  }
  kurs <- if (res$m$status == "fast") .fk_I1(valuta, res$m$base) else .fk_I(valuta, aar)
  res$x <- res$x / kurs
  res$m$valuta <- valuta
  res
}

.fk_sjekk_ikke_valuta <- function(m, navn) {
  if (!is.null(m$valuta)) {
    stop(navn, " er allerede i ", toupper(m$valuta),
         ". Regn om NOK-variabelen i stedet.", call. = FALSE)
  }
}

.fk_ny_etikett <- function(etikett, m) {
  paste0(etikett, ", ", .fk_beskriv(m))
}

#' Regn om beløp med KPI, lønnsindeks eller grunnbeløpet
#'
#' `fk_kr()` regner om én vektor. `fk_convert()` regner om kolonner i en
#' data.frame som har fått status med [fk_set()], og speiler Stata-kommandoen
#' `fafokr convert`.
#'
#' Omregningen bruker statusen til variabelen:
#' * løpende kroner deflateres direkte;
#' * faste kroner med samme deflator som `index` flyttes bare til nytt basisår;
#' * faste kroner med en annen deflator blåses først opp til løpende kroner med
#'   den opprinnelige deflatoren, og regnes så om med `index`;
#' * G-enheter ganges først med G for året.
#'
#' Med `index = "g_snitt"` eller `"g_mai"` og uten `to` blir resultatet
#' G-enheter (beløp delt på G i året). Med `to` blir det G-justerte kroner på
#' `to`-nivå. `index = "nominell"` gir løpende kroner.
#'
#' @param x Numerisk vektor.
#' @param aar Årstall for hver verdi (vektor av samme lengde, eller ett tall).
#' @param index `"kpi"`, `"lonn"`, `"g_snitt"`, `"g_mai"` eller `"nominell"`.
#' @param to Året beløpene skal uttrykkes i.
#' @param status,base,deflator Status for `x` hvis den ikke er satt med
#'   [fk_status()] eller [fk_set()].
#' @param currency `"usd"` eller `"eur"` for å regne resultatet om fra NOK med
#'   årsgjennomsnittet av Norges Banks valutakurs. Faste kroner (med `to`)
#'   bruker kursen i `to`-året; løpende kroner (`index = "nominell"`) bruker
#'   kursen for hvert år. Kan ikke kombineres med G-enheter.
#' @return `fk_kr()`: omregnet vektor med ny status. `fk_convert()`: `data` med
#'   nye eller erstattede kolonner.
#' @examples
#' # 500 000 løpende 2010-kroner i faste 2025-kroner (KPI)
#' \dontrun{fk_kr(500000, 2010, index = "kpi", to = 2025, status = "løpende")}
#' # Samme beløp i G-enheter
#' fk_kr(500000, 2010, index = "g_snitt", status = "løpende")
#' @export
fk_kr <- function(x, aar, index, to = NULL, status = NULL, base = NULL, deflator = NULL,
                  currency = NULL) {
  if (!is.numeric(x)) stop("x m\u00e5 v\u00e6re numerisk.", call. = FALSE)
  if (!is.numeric(aar)) stop("aar m\u00e5 v\u00e6re numerisk.", call. = FALSE)
  if (length(aar) == 1) aar <- rep(aar, length(x))
  if (length(aar) != length(x)) stop("aar og x har ulik lengde.", call. = FALSE)
  index <- .fk_norm_indeks(index, tillat_nominell = TRUE)
  currency <- .fk_norm_valuta(currency)
  m <- if (!is.null(status)) .fk_lag_status(status, NA_character_, base, deflator) else attr(x, "fafokr")
  if (is.null(m)) {
    stop("x har ingen status. Oppgi status (og eventuelt base og deflator), ",
         "eller bruk fk_status()/fk_set() f\u00f8rst.", call. = FALSE)
  }
  .fk_sjekk_ikke_valuta(m, "x")
  etikett <- m$etikett %||% attr(x, "label")
  res <- .fk_kjerne(as.numeric(x), aar, m, index, to)
  res <- .fk_til_valuta(res, aar, currency)
  .fk_varsle_mangler(x, res$x, aar, deparse(substitute(x)))
  ut <- res$x
  res$m$etikett <- etikett
  attr(ut, "fafokr") <- res$m
  if (!is.null(etikett)) attr(ut, "label") <- .fk_ny_etikett(etikett, res$m)
  ut
}

.fk_varsle_mangler <- function(x, ut, aar, navn) {
  ny <- is.na(ut) & !is.na(x)
  if (any(ny)) {
    aa <- sort(unique(aar[ny]))
    vis <- if (length(aa) > 8) paste(c(utils::head(aa, 8), "..."), collapse = ", ") else paste(aa, collapse = ", ")
    warning(sum(ny), " verdi(er) i ", navn, " ble manglende fordi indeksen mangler for \u00e5r: ",
            vis, call. = FALSE)
  }
}

#' @rdname fk_kr
#' @param data En data.frame.
#' @param cols Kolonnene som skal regnes om (tekst eller nakne navn).
#' @param prefix Prefiks for nye kolonner, f.eks. `"r_"`.
#' @param replace Erstatt kolonnene i stedet for å lage nye.
#' @export
fk_convert <- function(data, cols, index, to = NULL, prefix = NULL, replace = FALSE,
                       currency = NULL) {
  if (!is.data.frame(data)) stop("data m\u00e5 v\u00e6re en data.frame.", call. = FALSE)
  cols <- .fk_kolonnenavn(substitute(cols), parent.frame())
  index <- .fk_norm_indeks(index, tillat_nominell = TRUE)
  currency <- .fk_norm_valuta(currency)
  if (is.null(prefix) == !replace) {
    stop("Oppgi enten prefix (nye kolonner) eller replace = TRUE.", call. = FALSE)
  }
  mangler <- setdiff(cols, names(data))
  if (length(mangler)) stop("Finner ikke: ", paste(mangler, collapse = ", "), call. = FALSE)
  for (v in cols) {
    m <- attr(data[[v]], "fafokr")
    if (is.null(m)) stop(v, " har ingen fafokr-status. Bruk fk_set() f\u00f8rst.", call. = FALSE)
    .fk_sjekk_ikke_valuta(m, v)
    if (is.na(m$aar) || !m$aar %in% names(data)) {
      stop("\u00c5rsvariabelen for ", v, " (", m$aar, ") finnes ikke i data.", call. = FALSE)
    }
    if (!is.null(prefix) && paste0(prefix, v) %in% names(data)) {
      stop(paste0(prefix, v), " finnes allerede.", call. = FALSE)
    }
  }
  for (v in cols) {
    x <- data[[v]]
    m <- attr(x, "fafokr")
    aar <- data[[m$aar]]
    res <- .fk_kjerne(as.numeric(x), aar, m, index, to)
    res <- .fk_til_valuta(res, aar, currency)
    .fk_varsle_mangler(x, res$x, aar, v)
    ut <- res$x
    res$m$etikett <- m$etikett
    attr(ut, "fafokr") <- res$m
    attr(ut, "label") <- .fk_ny_etikett(m$etikett %||% v, res$m)
    ny <- if (replace) v else paste0(prefix, v)
    data[[ny]] <- ut
    message(sprintf("  %s -> %s: %s", v, ny, .fk_beskriv(res$m)))
  }
  if (index != "nominell") message("  Kilde: ", .fk_kildetekst(index))
  if (!is.null(currency)) message("  Kilde: ", .fk_kildetekst(currency))
  data
}

#' Grunnbeløpet på en dato eller for et år
#'
#' `fk_g()` gir G som gjaldt på en gitt dato. `fk_g_aar()` gir gjennomsnittlig
#' G for året (`type = "snitt"`) eller G per 1. mai (`type = "mai"`).
#'
#' @param dato Datoer (Date eller tekst på formen "ÅÅÅÅ-MM-DD").
#' @param aar Årstall.
#' @param type `"snitt"` eller `"mai"`.
#' @return Numerisk vektor.
#' @examples
#' fk_g("2024-06-15")
#' fk_g_aar(2020:2025)
#' @export
fk_g <- function(dato) {
  p <- .fk_data()$g
  perioder <- data.frame(dato = as.Date(p$fra_dato), g = p$g)
  .fk_g_paa(as.Date(dato), perioder)
}

#' @rdname fk_g
#' @export
fk_g_aar <- function(aar, type = c("snitt", "mai")) {
  type <- match.arg(type)
  .fk_I(paste0("g_", type), aar)
}

#' Valutakurs for et år
#'
#' Gir årsgjennomsnittet av Norges Banks valutakurs, i NOK per enhet.
#'
#' @param aar Årstall.
#' @param valuta `"usd"` eller `"eur"`.
#' @return Numerisk vektor.
#' @examples
#' \dontrun{fk_kurs(2020:2025, "eur")}
#' @export
fk_kurs <- function(aar, valuta = c("usd", "eur")) {
  valuta <- .fk_norm_valuta(match.arg(.fk_ascii(valuta[1]), .fk_valutaer))
  .fk_I(valuta, aar)
}
