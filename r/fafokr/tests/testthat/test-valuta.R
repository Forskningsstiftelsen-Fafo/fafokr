test_that("CSV fra Norges Bank leses i begge språkformater", {
  en <- fafokr:::.fk_nb_csv(falsk_les_tekst("norges-bank"))
  expect_equal(en$valuta[1], "usd")
  expect_equal(en$kurs[en$valuta == "eur" & en$periode == "1999"], 8)
  no <- fafokr:::.fk_nb_csv(falsk_les_tekst_fil("nb_exr_no.csv"))
  expect_equal(no$kurs[no$valuta == "sek"], 1.0075)   # notert per 100 SEK
  expect_equal(no$kurs[no$valuta == "usd"], 10.7471)  # desimalkomma
  expect_error(fafokr:::.fk_nb_csv("a;b\n1;2"), "mangler kolonnene")
})

test_that("valutakurser hentes, og inneværende år tas ikke med", {
  v <- with_mocked_bindings(fafokr:::.fk_hent_valuta(), .fk_les_tekst = falsk_les_tekst)
  iaar <- as.integer(format(Sys.Date(), "%Y"))
  expect_true(max(v$usd$aar) < iaar)
  expect_equal(min(v$eur$aar), 1999)
  expect_equal(v$usd$usd[v$usd$aar == 2020], 8.5)
  expect_match(v$url, "A.USD\\+EUR.NOK.SP")
})

test_that("fk_oppdater legger valuta inn i årstabellen og kildene", {
  mappe <- bruk_testdata()
  d <- fafokr:::.fk_les_mappe(mappe)
  expect_equal(d$aar$eur[d$aar$aar == 2009], 9)
  expect_true(all(c("usd", "eur") %in% d$kilder$serie))
  expect_equal(d$kilder$tabell[d$kilder$serie == "usd"], "EXR")
  expect_equal(fk_kurs(2020, "usd"), 8.5)
  expect_equal(fk_kurs(2009, "EUR"), 9)
})

test_that("gamle filer uten valutakolonner kan leses og oppdateres", {
  mappe <- bruk_testdata()
  aar <- utils::read.csv(file.path(mappe, "fafokr_aar.csv"))
  utils::write.csv(aar[, c("aar", "g_snitt", "g_mai", "kpi", "lonn")],
                   file.path(mappe, "fafokr_aar.csv"), row.names = FALSE, na = "")
  k <- utils::read.csv(file.path(mappe, "fafokr_kilder.csv"), colClasses = "character")
  utils::write.csv(k[k$serie %in% c("g", "kpi", "lonn"), ], file.path(mappe, "fafokr_kilder.csv"),
                   row.names = FALSE, na = "")
  gml <- fafokr:::.fk_les_mappe(mappe)
  expect_true(all(is.na(gml$aar$usd)))
  with_mocked_bindings(
    suppressMessages(fk_oppdater(mappe = mappe, cache = FALSE, forrige = mappe,
                                 serier = "valuta")),
    .fk_les_tekst = falsk_les_tekst)
  ny <- fafokr:::.fk_les_mappe(mappe)
  expect_equal(ny$aar$usd[ny$aar$aar == 2010], 6)
  expect_equal(ny$aar$kpi[ny$aar$aar == 2020], 115)   # KPI er beholdt
  expect_true("usd" %in% ny$kilder$serie)
})

test_that("omregning til valuta", {
  bruk_testdata()
  # Løpende kroner med årets kurs
  x <- fk_kr(c(85, 100), c(2020, 2014), "nominell", status = "l\u00f8pende", currency = "usd")
  expect_equal(as.numeric(x), c(85 / 8.5, 100 / 7))
  expect_equal(attr(x, "fafokr")$valuta, "usd")
  # Faste kroner med kursen i måleåret
  y <- fk_kr(100, 2015, "kpi", to = 2020, status = "lopende", currency = "eur")
  expect_equal(as.numeric(y), 100 * 115 / 100 / (8 + 0.1 * 21))
  # G-justerte kroner
  z <- fk_kr(2 * 89502, 2015, "g_snitt", to = 2020, status = "lopende", currency = "usd")
  expect_equal(as.numeric(z), 2 * 100853 / 8.5)
  # Feil
  expect_error(fk_kr(1, 2015, "g_snitt", status = "lopende", currency = "usd"), "G-enheter")
  expect_error(fk_kr(x, c(2020, 2014), "kpi", to = 2020), "allerede i USD")
  expect_error(fk_kr(1, 2015, "kpi", to = 2020, status = "lopende", currency = "sek"), "Ukjent valuta")
  expect_error(fk_kr(1, 2015, "kpi", to = 1990, status = "lopende", currency = "usd"), "KPI mangler|mangler for 1990")
  expect_warning(w <- fk_kr(1, 1995, "nominell", status = "lopende", currency = "eur"), "1995")
  expect_true(is.na(w))
  # Uten valuta skal 'nok' være det samme som ingen valuta
  expect_equal(as.numeric(fk_kr(1, 2015, "kpi", to = 2015, status = "lopende", currency = "nok")), 1)
})

test_that("fk_convert med currency setter etikett og status", {
  bruk_testdata()
  d <- data.frame(aar = c(2019, 2020), inntekt = c(100, 200))
  attr(d$inntekt, "label") <- "Inntekt"
  d <- fk_set(d, inntekt, aar = aar, status = "l\u00f8pende")
  d2 <- suppressMessages(fk_convert(d, inntekt, "kpi", to = 2020, prefix = "usd_",
                                    currency = "usd"))
  expect_equal(as.numeric(d2$usd_inntekt), c(100 * 115 / 112, 200) / 8.5)
  expect_equal(attr(d2$usd_inntekt, "label"), "Inntekt, faste 2020-kroner (KPI), i USD (2020-kurs)")
  expect_equal(fk_info(d2)$valuta, c(NA, "usd"))
  d3 <- suppressMessages(fk_convert(d, inntekt, "nominell", prefix = "e_", currency = "eur"))
  expect_equal(attr(d3$e_inntekt, "label"), "Inntekt, l\u00f8pende EUR (\u00e5rets kurs)")
  expect_message(fk_convert(d, inntekt, "nominell", prefix = "e_", currency = "eur"), "Norges Bank")
})
