# Felles testdata: ekte G-historikk fra Nav og syntetiske SSB-svar.
# Syntetisk KPI: årsgjennomsnitt = 100 + 3 * (år - 2015). Tabell 14700 har
# 2000-2026M09; tabell 14710 har 1990-2026M09 på et nivå som er 1,003 lavere.
# Syntetisk årslønn: 500 000 * 1.04^(år - 2010) kroner, 2010-2025 (2009 mangler),
# som gir lønnsindeksen 100 * 1.04^(år - 2025).
# Syntetiske valutakurser: USD = 6 + 0.25 * (år - 2010), EUR = 8 + 0.1 * (år - 1999).

fiks <- function(navn) test_path("fixtures", navn)

falsk_les_tekst <- function(kilde, forsok = 3) {
  fil <- if (grepl("g_historikk", kilde)) fiks("g_historikk.json")
    else if (grepl("14700/metadata", kilde)) fiks("ssb_14700_meta.json")
    else if (grepl("14700/data", kilde)) fiks("ssb_14700_data.json")
    else if (grepl("14710/metadata", kilde)) fiks("ssb_14710_meta.json")
    else if (grepl("14710/data", kilde)) fiks("ssb_14710_data.json")
    else if (grepl("14858/metadata", kilde)) fiks("ssb_14858_meta.json")
    else if (grepl("14858/data", kilde)) fiks("ssb_14858_data.json")
    else if (grepl("norges-bank", kilde)) fiks("nb_exr_a.csv")
    else stop("Ukjent testkilde: ", kilde)
  paste(readLines(fil, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

# Bygger et komplett testdatagrunnlag i en midlertidig mappe og tar det i bruk.
bruk_testdata <- function() {
  mappe <- tempfile("fafokr_test_")
  dir.create(mappe)
  with_mocked_bindings(
    suppressMessages(fk_oppdater(mappe = mappe, cache = FALSE, forrige = mappe,
                                 g_kilde = "g_historikk")),
    .fk_les_tekst = falsk_les_tekst
  )
  d <- fafokr:::.fk_les_mappe(mappe)
  d$type <- "test"
  assign("data", d, envir = fafokr:::.fk_env)
  invisible(mappe)
}

falsk_les_tekst_fil <- function(navn) {
  paste(readLines(fiks(navn), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
