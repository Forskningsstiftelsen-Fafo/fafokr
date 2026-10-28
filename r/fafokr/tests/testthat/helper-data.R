# Felles testdata: ekte G-historikk fra Nav og syntetiske SSB-svar.
# Syntetisk KPI: årsgjennomsnitt = 100 + 3 * (år - 2015), 2014-2025.
# Syntetisk lønnsindeks: 100 * 1.04^(år - 2010), 2010-2024 (2025 mangler).

fiks <- function(navn) test_path("fixtures", navn)

falsk_les_tekst <- function(kilde, forsok = 3) {
  fil <- if (grepl("g_historikk", kilde)) fiks("g_historikk.json")
    else if (grepl("03013/metadata", kilde)) fiks("ssb_03013_meta.json")
    else if (grepl("03013/data", kilde)) fiks("ssb_03013_data.json")
    else if (grepl("09786/metadata", kilde)) fiks("ssb_09786_meta.json")
    else if (grepl("09786/data", kilde)) fiks("ssb_09786_data.json")
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
