# Recorded measurement driver. Set LEGACY_SOURCE and BENCHMARK_DATA paths before running.
library(OECDdata)
library(data.table)
oecdOptions(quiet = TRUE, language = "en")
legacy <- new.env(parent = asNamespace("OECDdata"))
sys.source("LEGACY_SOURCE/R/xml.R", envir = legacy)
bench <- function(label, path, ref = NULL) {
  old <- function() if (is.null(ref)) legacy$.parse_catalogue(xml2::read_xml(path, options=c("NOBLANKS", "NONET"))) else
    legacy$.parse_structure(xml2::read_xml(path, options=c("NOBLANKS", "NONET")),ref)
  new <- function() if (is.null(ref)) OECDdata:::.parse_catalogue(OECDdata:::.read_xml(path)) else
    OECDdata:::.parse_structure(OECDdata:::.read_xml(path),ref)
  cat("\n", label, ": ", file.info(path)$size, " bytes\n", sep="")
  print(system.time(a <- old()))
  print(system.time(b <- new()))
  print(all.equal(a,b))
  stopifnot(isTRUE(all.equal(a,b)))
  times <- rbindlist(lapply(c("old","new"), function(which) {
    f <- if(which == "old") old else new
    rbindlist(lapply(seq_len(3L), function(i) {
      gc()
      elapsed <- system.time(f())
      data.table(input=label,parser=which,iteration=i,user=elapsed[["user.self"]],system=elapsed[["sys.self"]],elapsed=elapsed[["elapsed"]])
    }))
  }))
  print(times)
  fwrite(times,paste0("BENCHMARK_DATA/",label,"-times.csv"))
  saveRDS(b,paste0("BENCHMARK_DATA/",label,"-result.rds"))
}
bench("catalogue", "BENCHMARK_DATA/catalogue.xml")
bench("cli-structure", "BENCHMARK_DATA/cli-structure.xml", list(agency="OECD.SDD.STES",id="DSD_STES@DF_CLI",version="4.1"))
