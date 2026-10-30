test_that("G-historikken fra Nav leses riktig", {
  g <- fafokr:::.fk_g_fra_json(falsk_les_tekst("g_historikk"))
  expect_equal(nrow(g), 73)
  expect_equal(g$dato[1], as.Date("1967-01-01"))
  expect_equal(g$g[g$dato == as.Date("2026-05-01")], 136549)
  tab <- expect_silent(fafokr:::.fk_g_tabeller(g))   # ingen avvik mot Navs snitt
  aar <- tab$aar
  expect_equal(aar$g_snitt[aar$aar == 1990], 33575)   # endring 1.5 og 1.12
  expect_equal(aar$g_mai[aar$aar == 1990], 34000)
  expect_equal(aar$g_snitt[aar$aar == 1981], 18658)   # tre endringer
  expect_equal(aar$g_mai[aar$aar == 1988], 31000)     # endring 1.4
  expect_equal(aar$g_snitt[aar$aar == 2025], 128116)
  expect_equal(tab$perioder$til_dato[tab$perioder$fra_dato == "2025-05-01"], "2026-04-30")
  expect_true(is.na(tail(tab$perioder$til_dato, 1)))
})

test_that("G-data som ikke stiger, avvises", {
  feil <- '[{"dato":"2020-05-01","grunnbel\u00f8p":100},{"dato":"2021-05-01","grunnbel\u00f8p":90}]'
  expect_error(fafokr:::.fk_g_fra_json(feil), "stigende")
})

test_that("JSON-stat2 leses i både tett og glissen form", {
  kpi <- fafokr:::.fk_jsonstat(falsk_les_tekst("14700/data"))
  expect_equal(kpi$Tid[1], "2000M01")
  expect_equal(kpi$verdi[kpi$Tid == "2015M06"], 99.95)
  lonn <- fafokr:::.fk_jsonstat(falsk_les_tekst("14858/data"))
  expect_true(is.na(lonn$verdi[lonn$Tid == "2009"]))
  expect_equal(lonn$verdi[lonn$Tid == "2011"], 520000)
  meta <- fafokr:::.fk_jsonstat(falsk_les_tekst("14700/metadata"), med_verdier = FALSE)
  expect_equal(meta$koder$VareTjenesteGrp, c("00", "01", "02"))
})

test_that("KPI (14700/14710) og lønnsindeks (14858) hentes og kontrolleres", {
  with_mocked_bindings({
    k <- fafokr:::.fk_hent_kpi()
    l <- fafokr:::.fk_hent_lonn()
  }, .fk_les_tekst = falsk_les_tekst)
  expect_equal(k$aar$aar, 1990:2025)                # 2026 er ikke et helt år
  expect_equal(k$aar$kpi, 100 + 3 * (1990:2025 - 2015), tolerance = 1e-5)
  expect_equal(k$faktor, 1.003, tolerance = 1e-5)
  expect_equal(nrow(k$mnd), 36 * 12 + 9)
  # Fra 2000 er tallene akkurat de i 14700
  expect_equal(k$mnd$kpi[k$mnd$aar == 2000 & k$mnd$mnd == 1], round(55 - 0.55, 4))
  expect_match(k$url, "14700/data.*valueCodes\\[VareTjenesteGrp\\]=00")
  expect_match(k$url, "valueCodes\\[ContentsCode\\]=KPIIndMnd")
  expect_match(k$url, "14710/data.*valueCodes\\[ContentsCode\\]=KPIHist&")
  expect_equal(l$aar$aar, 2010:2025)
  expect_equal(l$aar$lonn[l$aar$aar == 2025], 100)
  expect_equal(l$aar$lonn, 100 * 1.04^(2010:2025 - 2025), tolerance = 1e-5)
  expect_match(l$url, "14858/data.*valueCodes\\[ContentsCode\\]=Arslonn&")
})

test_that("KPI-tabeller som ikke passer sammen, avvises", {
  feil_nivaa <- function(kilde, forsok = 3) {
    tekst <- falsk_les_tekst(kilde)
    if (grepl("14710/data", kilde)) {
      js <- jsonlite::fromJSON(tekst, simplifyVector = FALSE)
      js$value <- lapply(js$value, function(v) v * 0.5)
      tekst <- jsonlite::toJSON(js, auto_unbox = TRUE, digits = NA)
    }
    tekst
  }
  expect_error(with_mocked_bindings(fafokr:::.fk_hent_kpi(), .fk_les_tekst = feil_nivaa),
               "passer ikke sammen")
})

test_that("fk_oppdater skriver filer og beholder gamle tall ved feil", {
  mappe <- bruk_testdata()
  expect_true(all(file.exists(file.path(mappe, fafokr:::.fk_filer))))
  k <- fafokr:::.fk_les_mappe(mappe)$kilder
  expect_equal(k$tabell[k$serie == "kpi"], "14700 (f\u00f8r 2000: 14710)")
  expect_equal(k$basis[k$serie == "kpi"], "2025=100")
  expect_false(anyNA(k$hentet))

  # Ny kjøring der SSB feiler: KPI og lønn skal beholdes.
  feil_ssb <- function(kilde, forsok = 3) {
    if (grepl("ssb", kilde)) stop("nede") else falsk_les_tekst(kilde)
  }
  expect_warning(expect_warning(
    with_mocked_bindings(
      suppressMessages(fk_oppdater(mappe = mappe, cache = FALSE, forrige = mappe,
                                   g_kilde = "g_historikk")),
      .fk_les_tekst = feil_ssb),
    "KPI"), "l\u00f8nnsindeksen")
  aar <- fafokr:::.fk_les_mappe(mappe)$aar
  expect_equal(aar$kpi[aar$aar == 2020], 115)
  expect_equal(aar$lonn[aar$aar == 2025], 100)
})

test_that("lønnsindeksen krever basisåret og en entydig serie", {
  uten_2025 <- function(kilde, forsok = 3) {
    tekst <- falsk_les_tekst(kilde)
    if (grepl("14858/data", kilde)) {
      js <- jsonlite::fromJSON(tekst, simplifyVector = FALSE)
      js$value[["16"]] <- NULL          # 2025
      tekst <- jsonlite::toJSON(js, auto_unbox = TRUE, digits = NA)
    }
    tekst
  }
  expect_error(with_mocked_bindings(fafokr:::.fk_hent_lonn(), .fk_les_tekst = uten_2025),
               "basis\u00e5ret 2025")
  to_serier <- function(kilde, forsok = 3) {
    tekst <- falsk_les_tekst(kilde)
    if (grepl("14858/metadata", kilde)) {
      tekst <- sub("Real annual earnings in 2025-prices (NOK)", "Annual earnings, other (NOK)",
                   tekst, fixed = TRUE)
    }
    tekst
  }
  expect_error(with_mocked_bindings(fafokr:::.fk_hent_lonn(), .fk_les_tekst = to_serier),
               "entydig")
})
