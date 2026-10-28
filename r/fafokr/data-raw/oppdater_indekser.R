# Oppdaterer øyeblikksbildet som følger med pakkene.
#
# Kjøres av vedlikeholder (eller GitHub Actions) med internettilgang:
#   Rscript r/fafokr/data-raw/oppdater_indekser.R
# Skriptet henter G, KPI og lønnsindeks, kontrollerer tallene og skriver
# de samme fire CSV-filene til
#   r/fafokr/inst/extdata/   (R-pakken)
#   stata/                   (Stata-pakken)
# Bygg og installer pakkene på nytt etterpå, så følger de nye tallene med.
#
# Valgfritt argument: sti eller URL til G i API-format, f.eks. en lokal kopi
# av grunnbeløp.json fra github.com/navikt/g:
#   Rscript r/fafokr/data-raw/oppdater_indekser.R /sti/til/grunnbeløp.json

args <- commandArgs(trailingOnly = FALSE)
fil <- sub("^--file=", "", args[grepl("^--file=", args)])
pakke <- if (length(fil)) normalizePath(file.path(dirname(fil), "..")) else getwd()
g_kilde <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(g_kilde)) g_kilde <- NULL

# Bruk kildekoden direkte, så skriptet virker uten at pakken er installert.
for (f in list.files(file.path(pakke, "R"), full.names = TRUE, pattern = "[.]R$")) {
  source(f, encoding = "UTF-8")
}

extdata <- file.path(pakke, "inst", "extdata")
stata <- normalizePath(file.path(pakke, "..", "..", "stata"), mustWork = FALSE)

kilder <- fk_oppdater(
  mappe = c(extdata, if (dir.exists(stata)) stata),
  cache = FALSE,
  forrige = extdata,
  g_kilde = g_kilde
)
print(kilder[, c("serie", "hentet", "forste_aar", "siste_aar")])
