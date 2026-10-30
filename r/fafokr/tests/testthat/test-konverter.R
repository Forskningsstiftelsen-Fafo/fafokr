test_that("løpende kroner deflateres med KPI og lønnsindeks", {
  bruk_testdata()
  expect_equal(as.numeric(fk_kr(100, 2015, "kpi", to = 2018, status = "l\u00f8pende")), 109)
  expect_equal(as.numeric(fk_kr(100, 2015, "lonn", to = 2016, status = "lopende")),
               100 * 1.04^6 / 1.04^5, tolerance = 1e-6)
  x <- fk_kr(c(100, 200), c(2015, 2016), "kpi", to = 2015, status = "lopende")
  expect_equal(as.numeric(x), c(100, 200 * 100 / 103))
  expect_equal(attr(x, "fafokr")$status, "fast")
  expect_equal(attr(x, "fafokr")$base, 2015L)
})

test_that("faste kroner flyttes til nytt basisår og ny deflator", {
  bruk_testdata()
  # Samme deflator: bare nytt basisår, uavhengig av årstallet.
  expect_equal(as.numeric(fk_kr(100, 2030, "kpi", to = 2018, status = "fast",
                                base = 2015, deflator = "kpi")), 109)
  # Annen deflator: blås opp med KPI, deflater med lønn.
  x <- fk_kr(100, 2016, "lonn", to = 2020, status = "fast", base = 2015, deflator = "kpi")
  nom <- 100 * 103 / 100
  expect_equal(as.numeric(x), nom * 1.04^10 / 1.04^6, tolerance = 1e-6)
})

test_that("G-enheter og G-justerte kroner", {
  bruk_testdata()
  g24 <- fk_g_aar(2024)
  expect_equal(g24, 122225)
  expect_equal(as.numeric(fk_kr(2 * g24, 2024, "g_snitt", status = "lopende")), 2)
  expect_equal(as.numeric(fk_kr(2 * 124028, 2024, "g_mai", status = "lopende")), 2)
  # G-justert til 2025-nivå
  expect_equal(as.numeric(fk_kr(g24, 2024, "g", to = 2025, status = "lopende")), 128116)
  # Fra G-enheter til KPI-kroner
  x <- fk_kr(1, 2020, "kpi", to = 2015, status = "g", deflator = "g_snitt")
  expect_equal(as.numeric(x), 100853 * 100 / 115)
  # Fra G (snitt) til G (mai)
  y <- fk_kr(1, 2020, "g_mai", status = "g", deflator = "g_snitt")
  expect_equal(as.numeric(y), 100853 / 101351)
})

test_that("rundturer gir tilbake utgangspunktet", {
  bruk_testdata()
  x <- fk_status(c(400000, 500000, 600000), "l\u00f8pende")
  aar <- c(2016, 2019, 2022)
  g <- fk_kr(x, aar, "g_snitt")
  expect_equal(as.numeric(fk_kr(g, aar, "nominell")), as.numeric(x))
  r <- fk_kr(x, aar, "kpi", to = 2020)
  expect_equal(as.numeric(fk_kr(r, aar, "nominell")), as.numeric(x))
  l <- fk_kr(r, aar, "lonn", to = 2012)   # KPI-kroner -> lønnsjustert
  expect_equal(as.numeric(fk_kr(l, aar, "nominell")), as.numeric(x))
})

test_that("manglende år gir NA med advarsel, manglende målår gir feil", {
  bruk_testdata()
  expect_warning(x <- fk_kr(c(1, 1), c(2015, 1985), "kpi", to = 2015, status = "lopende"),
                 "1985")
  expect_true(is.na(x[2]))
  expect_error(fk_kr(1, 2015, "kpi", to = 2026, status = "lopende"), "mangler for 2026")
  expect_error(fk_kr(1, 2015, "kpi", status = "lopende"), "Oppgi til hvilket")
  expect_error(fk_kr(1, 2015, "kpi", to = 2020), "ingen status")
})

test_that("feil status gir tydelige meldinger", {
  expect_error(fk_status(1, "fast"), "base")
  expect_error(fk_status(1, "fast", base = 2015), "deflator")
  expect_error(fk_status(1, "g", deflator = "kpi"), "g_snitt eller g_mai")
  expect_error(fk_status(1, "l\u00f8pende", base = 2015), "skal ikke")
  expect_error(fk_status(1, "nominal-ish"), "Ukjent status")
  expect_error(fk_kr(1, 2015, "ppi", to = 2020, status = "lopende"), "Ukjent indeks")
})

test_that("fk_set, fk_convert og fk_info virker på data.frame", {
  bruk_testdata()
  d <- data.frame(aar = c(2015, 2016, 2017), inntekt = c(100, 200, 300),
                  pensjon15 = c(10, 20, 30))
  attr(d$inntekt, "label") <- "Inntekt"
  d <- fk_set(d, inntekt, aar = aar, status = "l\u00f8pende")
  d <- fk_set(d, "pensjon15", aar = "aar", status = "fast", base = 2015, deflator = "kpi")
  expect_error(fk_set(d, inntekt, aar = aar, status = "lopende"), "allerede status")
  info <- fk_info(d)
  expect_equal(info$variabel, c("inntekt", "pensjon15"))

  expect_error(fk_convert(d, inntekt, "kpi", to = 2017), "prefix")
  expect_message(d2 <- fk_convert(d, c(inntekt, pensjon15), "kpi", to = 2017, prefix = "r_"),
                 "Kilde")
  expect_equal(as.numeric(d2$r_inntekt), c(100 * 106 / 100, 200 * 106 / 103, 300))
  expect_equal(as.numeric(d2$r_pensjon15), c(10, 20, 30) * 106 / 100)
  expect_equal(attr(d2$r_inntekt, "label"), "Inntekt, faste 2017-kroner (KPI)")
  expect_equal(attr(d2$r_inntekt, "fafokr")$aar, "aar")
  expect_error(fk_convert(d2, inntekt, "kpi", to = 2017, prefix = "r_"), "finnes allerede")

  # Kjedet omregning: KPI-kroner -> G-enheter
  d3 <- suppressMessages(fk_convert(d2, r_inntekt, "g_snitt", prefix = "g_"))
  expect_equal(as.numeric(d3$g_r_inntekt), c(100, 200, 300) / fk_g_aar(2015:2017))
  expect_equal(attr(d3$g_r_inntekt, "label"), "Inntekt, G-enheter (gj.snittlig G)")

  d4 <- suppressMessages(fk_convert(d, inntekt, "g_snitt", replace = TRUE))
  expect_equal(attr(d4$inntekt, "fafokr")$status, "g")
})

test_that("G på dato", {
  bruk_testdata()
  expect_equal(fk_g(c("2024-04-30", "2024-05-01", "1966-12-31")), c(118620, 124028, NA))
  expect_equal(fk_g(as.Date("1990-12-15")), 34100)
  expect_equal(fk_g_aar(1990, "mai"), 34000)
})

test_that("indeks som mangler i datagrunnlaget gir råd om fk_oppdater", {
  bruk_testdata()
  d <- fafokr:::.fk_env$data
  d$aar$kpi <- NA_real_
  assign("data", d, envir = fafokr:::.fk_env)
  expect_error(fk_kr(1, 2015, "kpi", to = 2020, status = "lopende"), "fk_oppdater")
  fafokr:::.fk_nullstill()
})
