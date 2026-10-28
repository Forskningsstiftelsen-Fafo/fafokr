# Hjelpefunksjoner og konstanter som brukes i hele pakken.
# Merk: norske bokstaver i strenger er skrevet som \u-koder (ø = ø,
# å = å, æ = æ) slik at kildekoden er ren ASCII og portabel.

# Filnavnene i datagrunnlaget. Samme filer brukes av Stata-versjonen.
.fk_filer <- c(
  aar     = "fafokr_aar.csv",
  g       = "fafokr_g.csv",
  kpi_mnd = "fafokr_kpi_mnd.csv",
  kilder  = "fafokr_kilder.csv"
)

# Indeksene som kan brukes til omregning.
.fk_indekser <- c("kpi", "lonn", "g_snitt", "g_mai")
.fk_g_indekser <- c("g_snitt", "g_mai")

# Hvilken rad i kildetabellen hver indeks hører til.
.fk_serie_for_indeks <- c(kpi = "kpi", lonn = "lonn", g_snitt = "g", g_mai = "g")

.fk_indeksnavn <- c(
  kpi     = "KPI",
  lonn    = "l\u00f8nnsindeks",
  g_snitt = "gj.snittlig G",
  g_mai   = "G per 1. mai"
)

# Gjør tekst om til små bokstaver uten æ, ø og å.
.fk_ascii <- function(x) {
  x <- tolower(x)
  x <- gsub("\u00e6", "ae", x)
  x <- gsub("\u00f8", "o", x)
  x <- gsub("\u00e5", "a", x)
  trimws(x)
}

# Normaliserer status: "løpende", "lopende", "nominell" -> "lopende" osv.
.fk_norm_status <- function(status) {
  if (is.null(status)) return(NULL)
  s <- .fk_ascii(status)
  if (length(s) != 1) stop("status m\u00e5 v\u00e6re \u00e9n verdi.", call. = FALSE)
  if (s %in% c("lopende", "nominell", "nominal", "lop")) return("lopende")
  if (s %in% c("fast", "faste", "real", "deflatert")) return("fast")
  if (s %in% c("g", "g-enheter", "genheter", "g_enheter")) return("g")
  stop("Ukjent status \"", status, "\". Bruk \"l\u00f8pende\", \"fast\" eller \"g\".",
       call. = FALSE)
}

# Normaliserer indeks-/deflatornavn.
.fk_norm_indeks <- function(indeks, tillat_nominell = FALSE) {
  if (is.null(indeks)) return(NULL)
  s <- .fk_ascii(indeks)
  if (length(s) != 1) stop("Indeksen m\u00e5 v\u00e6re \u00e9n verdi.", call. = FALSE)
  s <- switch(s,
    "kpi" = , "cpi" = "kpi",
    "lonn" = , "lonnsindeks" = , "wage" = , "arslonn" = "lonn",
    "g" = , "g_snitt" = , "snitt" = , "gsnitt" = "g_snitt",
    "g_mai" = , "mai" = , "gmai" = "g_mai",
    "nominell" = , "lopende" = , "nominal" = "nominell",
    s
  )
  gyldige <- c(.fk_indekser, if (tillat_nominell) "nominell")
  if (!s %in% gyldige) {
    stop("Ukjent indeks \"", indeks, "\". Gyldige verdier: ",
         paste(gyldige, collapse = ", "), ".", call. = FALSE)
  }
  s
}

# Henter navnet på kolonner fra enten tekst eller nakne navn (NSE).
.fk_kolonnenavn <- function(uttrykk, env) {
  verdi <- tryCatch(eval(uttrykk, envir = env), error = function(e) NULL)
  if (is.character(verdi)) return(verdi)
  all.vars(uttrykk)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
