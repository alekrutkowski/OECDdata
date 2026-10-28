# The oracle deliberately uses xml2 only. Comparing two inputs passed to the
# new parser would not detect a regression shared by both native paths.
native_test_catalogue_reference <- function(text, language) {
  doc <- xml2::read_xml(text, options = c("NOBLANKS", "NONET"))
  children <- function(node, name)
    xml2::xml_find_all(node, paste0("./*[local-name()='", name, "']"))
  attr0 <- function(node, name) {
    value <- xml2::xml_attr(node, name)
    value[is.na(value)] <- ""
    value
  }
  text0 <- function(node) {
    value <- xml2::xml_text(node, trim = TRUE)
    value[is.na(value)] <- ""
    value
  }
  localized <- function(node, name = "Name", fallback = "") {
    candidates <- children(node, name)
    if (!length(candidates)) return(fallback)
    lang <- attr0(candidates, "lang")
    at <- c(which(lang == language), which(lang == "en"), seq_along(candidates))
    text0(candidates[[at[[1L]]]])
  }
  annotation <- function(node, types) {
    items <- xml2::xml_find_all(node, ".//*[local-name()='Annotation']")
    names <- vapply(items, function(x) text0(xml2::xml_find_first(x,
      "./*[local-name()='AnnotationType']")), character(1))
    at <- match(types, names)
    at <- at[!is.na(at)]
    if (!length(at)) return(NA_character_)
    item <- items[[at[[1L]]]]
    title <- text0(xml2::xml_find_first(item, "./*[local-name()='AnnotationTitle']"))
    if (nzchar(title)) title else localized(item, "AnnotationText")
  }
  flows <- xml2::xml_find_all(doc, ".//*[local-name()='Dataflow']")
  flows <- flows[nzchar(attr0(flows, "agencyID")) & nzchar(attr0(flows, "id"))]
  rows <- data.table::rbindlist(lapply(flows, function(f) {
    agency <- attr0(f, "agencyID")
    id <- attr0(f, "id")
    version <- attr0(f, "version")
    data.table::data.table(
      `Dataset name` = localized(f, fallback = id),
      Code = paste(agency, id, version, sep = ","), Type = "dataset",
      `Last update of data` = annotation(f, c("UPDATE_DATA", "LAST_UPDATE")),
      `Last table structure change` = annotation(f, "UPDATE_STRUCTURE"),
      `Data start` = annotation(f, "OBS_PERIOD_OVERALL_OLDEST"),
      `Data end` = annotation(f, "OBS_PERIOD_OVERALL_LATEST"),
      Link = paste0("https://data-explorer.oecd.org/vis?lc=", curl::curl_escape(language),
        "&df[ds]=dsDisseminateFinalDMZ&df[ag]=", curl::curl_escape(agency),
        "&df[id]=", curl::curl_escape(id), "&df[vs]=", curl::curl_escape(version)),
      Agency = agency, Dataflow = id, Version = version,
      Description = localized(f, "Description"))
  }))
  # Numeric version ordering and all final public columns are checked too.
  newest <- function(versions) Reduce(function(i, j)
    if (utils::compareVersion(versions[[i]], versions[[j]]) >= 0L) i else j,
    seq_along(versions), init = 1L)
  rows <- rows[, .SD[newest(Version)], by = c("Agency", "Dataflow")]
  data.table::set(rows, j = "ShortCode", value =
    OECDdata:::.catalogue_short_codes(rows$Dataflow))
  data.table::set(rows, j = "DataflowPrefix", value =
    OECDdata:::.dataflow_parts(rows$Dataflow)$prefix)
  data.table::setcolorder(rows, c("ShortCode", "Dataset name", "Code", "Agency", "Dataflow",
    "DataflowPrefix", "Version", "Type", "Last update of data", "Last table structure change",
    "Data start", "Data end", "Description", "Link"))
  data.table::setorderv(rows, c("Agency", "Dataflow"))
  rows
}

native_test_catalogue <- function() paste0(
  '<m:Structure xmlns:m="urn:message" xmlns:s="urn:structure" xmlns:c="urn:common">',
  '<s:Dataflows>',
  '<s:Dataflow agencyID="B" id="DSD@DF_MIX" version="1.9">',
  '<c:Name xml:lang="en">Old English</c:Name></s:Dataflow>',
  '<s:Dataflow agencyID="B" id="DSD@DF_MIX" version="1.10">',
  '<c:Name xml:lang="de">Deutsch</c:Name><c:Name xml:lang="en"> English &amp; XML </c:Name>',
  '<c:Name xml:lang="fr"> Fran&#231;ais </c:Name>',
  '<c:Name xml:lang="fr">Second French name</c:Name>',
  '<c:Description xml:lang="en"> A <![CDATA[<literal>]]> <c:b>nested</c:b> description </c:Description>',
  '<c:Annotations>',
  '<c:Annotation><c:AnnotationType>LAST_UPDATE</c:AnnotationType>',
  '<c:AnnotationTitle>fallback date</c:AnnotationTitle></c:Annotation>',
  '<c:Annotation><c:AnnotationType>UPDATE_DATA</c:AnnotationType>',
  '<c:AnnotationTitle> preferred date </c:AnnotationTitle></c:Annotation>',
  '<c:Annotation><c:AnnotationType>UPDATE_DATA</c:AnnotationType>',
  '<c:AnnotationTitle>duplicate ignored</c:AnnotationTitle></c:Annotation>',
  '<c:Annotation><c:AnnotationType>UPDATE_STRUCTURE</c:AnnotationType>',
  '<c:AnnotationTitle> \t </c:AnnotationTitle>',
  '<c:AnnotationText xml:lang="en"> English structure </c:AnnotationText>',
  '<c:AnnotationText xml:lang="fr"> Structure fran&#231;aise </c:AnnotationText></c:Annotation>',
  '<c:Annotation><c:AnnotationType>OBS_PERIOD_OVERALL_OLDEST</c:AnnotationType>',
  '<c:AnnotationTitle>2000-01</c:AnnotationTitle></c:Annotation>',
  '<c:Annotation><c:AnnotationType>OBS_PERIOD_OVERALL_LATEST</c:AnnotationType>',
  '<c:AnnotationTitle>2024-12</c:AnnotationTitle></c:Annotation>',
  '</c:Annotations></s:Dataflow>',
  '<s:Dataflow agencyID="A" id="DSD@DF_EMPTY" version="2.0">',
  '<c:Description/><c:Annotations>',
  '<c:Annotation><c:AnnotationType>UPDATE_DATA</c:AnnotationType></c:Annotation>',
  '<c:Annotation><c:AnnotationType>LAST_UPDATE</c:AnnotationType>',
  '<c:AnnotationTitle>must not replace empty preferred annotation</c:AnnotationTitle>',
  '</c:Annotation></c:Annotations></s:Dataflow>',
  '<s:Dataflow agencyID="A" id="DSD@DF_MIX" version="1.0"><c:Name/></s:Dataflow>',
  '<s:Dataflow agencyID="A &amp; B" id="DF_ESCAPED@x+y" version="1.0">',
  '<c:Name xml:lang="de">First available</c:Name></s:Dataflow>',
  '<s:Dataflow agencyID="C" id="DF_TIE" version="1.0"><c:Name>First tie</c:Name></s:Dataflow>',
  '<s:Dataflow agencyID="C" id="DF_TIE" version="1.0"><c:Name>Later tie</c:Name></s:Dataflow>',
  '<s:Dataflow agencyID="" id="IGNORED" version="1.0"/>',
  '<s:Dataflow agencyID="A" version="1.0"/>',
  '</s:Dataflows><s:ConstraintAttachment><s:Dataflow>',
  '<Ref agencyID="B" id="DSD@DF_MIX" version="1.10"/>',
  '</s:Dataflow></s:ConstraintAttachment></m:Structure>')

test_that("bulk native catalogue extraction matches the independent xml2 oracle", {
  text <- native_test_catalogue()
  doc <- OECDdata:::.read_xml(text, is_file = FALSE)
  invisible(lapply(c("en", "fr", "xx"), function(language) {
    local_oecd(language = language)
    expected <- native_test_catalogue_reference(text, language)
    actual <- OECDdata:::.parse_catalogue(doc)
    expect_identical(as.data.frame(actual), as.data.frame(expected))
    expect_identical(actual[Agency == "B"]$Version, "1.10")
    expect_identical(actual[Dataflow == "DF_TIE"]$`Dataset name`, "First tie")
    expect_true(all(is.na(actual[Dataflow == "DSD@DF_MIX"]$ShortCode)))
    expect_identical(actual[Dataflow == "DSD@DF_EMPTY"]$`Dataset name`, "DSD@DF_EMPTY")
    expect_identical(actual[Dataflow == "DSD@DF_EMPTY"]$`Last update of data`, "")
  }))
})

test_that("native catalogue extraction excludes attachment references and rejects empty catalogues", {
  doc <- OECDdata:::.read_xml('<root><Dataflow><Ref agencyID="A" id="FLOW"/></Dataflow></root>',
    is_file = FALSE)
  expect_error(OECDdata:::.parse_catalogue(doc), class = "OECDdata_metadata_error")
  doc <- OECDdata:::.read_xml('<root><Dataflow agencyID="A" id="FLOW" version="draft"/></root>',
    is_file = FALSE)
  expect_error(OECDdata:::.parse_catalogue(doc), "Non-numeric")
})

test_that("native document indexes preserve descendant order and subtree scope", {
  doc <- OECDdata:::.read_xml(paste0('<root><Dataflow id="first"><Dataflow id="nested"/>',
    '<x><Codelist id="inside"/></x></Dataflow><Dataflow id="last"/>',
    '<Codelist id="outside"/></root>'), is_file = FALSE)
  flows <- OECDdata:::.descendants(doc, "Dataflow")
  expect_identical(OECDdata:::.attr(flows, "id"), c("first", "nested", "last"))
  expect_identical(OECDdata:::.attr(OECDdata:::.children(doc, "Dataflow"), "id"),
    c("first", "last"))
  expect_identical(OECDdata:::.attr(OECDdata:::.descendants(flows[[1L]], "Codelist"), "id"),
    "inside")
  expect_length(OECDdata:::.children(flows[[1L]], "Codelist"), 0L)
  expect_identical(OECDdata:::.attr(OECDdata:::.descendants(doc, "Codelist"), "id"),
    c("inside", "outside"))
})

test_that("native localization preserves missing, empty and exact-language semantics", {
  doc <- OECDdata:::.read_xml(paste0('<root><Item id="none"/><Item id="empty"><Name/></Item>',
    '<Item id="languages"><Name xml:lang="de"> First </Name>',
    '<Name xml:lang="en"> English </Name><Name xml:lang="fr"> French </Name>',
    '<Name xml:lang="fr"> Later French </Name></Item>',
    '<Item id="regional"><Name xml:lang="fr-CA"> Regional </Name>',
    '<Name xml:lang="en"> English fallback </Name></Item></root>'), is_file = FALSE)
  nodes <- OECDdata:::.children(doc, "Item")
  local_oecd(language = "fr")
  expect_identical(OECDdata:::.localized(nodes[[1L]], fallback = "fallback"), "fallback")
  expect_identical(OECDdata:::.localized(nodes[[2L]], fallback = "fallback"), "")
  expect_identical(OECDdata:::.localized(nodes[[3L]]), "French")
  expect_identical(OECDdata:::.localized(nodes[[4L]]), "English fallback")
  local_oecd(language = "xx")
  expect_identical(OECDdata:::.localized(nodes[[3L]]), "English")
  local_oecd(language = "de")
  expect_identical(OECDdata:::.localized(nodes[[3L]]), "First")
})

test_that("native text and attributes decode XML and preserve Unicode", {
  doc <- OECDdata:::.read_xml(paste0('<root xmlns:q="urn:test"><q:Item id="A&amp;B" xml:lang="fr">',
    ' \tFran&#231;ais &amp; &#x1F600; <![CDATA[<literal>]]> <q:b>nested</q:b> \n',
    '</q:Item><q:Item/></root>'), is_file = FALSE)
  nodes <- OECDdata:::.children(doc, "Item")
  expect_identical(OECDdata:::.attr(nodes, "id", "missing"), c("A&B", "missing"))
  expect_identical(OECDdata:::.attr(nodes, "lang", "missing"), c("fr", "missing"))
  expect_identical(OECDdata:::.text(nodes), c("Fran\u00e7ais & \U0001f600 <literal> nested", ""))
  expect_identical(OECDdata:::.text(list()), character())
  expect_identical(OECDdata:::.attr(list(), "id"), character())
  expect_identical(OECDdata:::.text(NULL, "missing"), "missing")
  expect_identical(OECDdata:::.attr(NULL, "id", "missing"), "missing")
})

test_that("native annotations retain first matches and prefer nonempty titles", {
  doc <- OECDdata:::.read_xml(native_test_catalogue(), is_file = FALSE)
  flow <- OECDdata:::.first(doc, ".//*[local-name()='Dataflow' and @version='1.10']")
  local_oecd(language = "fr")
  annotations <- OECDdata:::.annotations(flow)
  expect_identical(names(annotations), c("LAST_UPDATE", "UPDATE_DATA", "UPDATE_DATA",
    "UPDATE_STRUCTURE", "OBS_PERIOD_OVERALL_OLDEST", "OBS_PERIOD_OVERALL_LATEST"))
  expect_identical(unname(annotations[2:4]),
    c("preferred date", "duplicate ignored", "Structure fran\u00e7aise"))
  expect_identical(OECDdata:::.annotation(annotations, c("UPDATE_DATA", "LAST_UPDATE")),
    "preferred date")
  expect_identical(OECDdata:::.annotations(NULL), character())
})

test_that("bulk codelists preserve order, empty labels and leading zero identifiers", {
  doc <- OECDdata:::.read_xml(paste0('<root><Codelist><Code id="00"><Name xml:lang="fr"> Z\u00e9ro </Name>',
    '<Name xml:lang="en">Zero</Name></Code><Code id="01"><Name/></Code><Code id="02"/>',
    '<Extra><Code id="nested"><Name>not a direct child</Name></Code></Extra>',
    '</Codelist><Codelist/></root>'), is_file = FALSE)
  lists <- OECDdata:::.children(doc, "Codelist")
  local_oecd(language = "fr")
  expect_identical(OECDdata:::.codes(lists[[1L]]),
    data.table::data.table(code = c("00", "01", "02"), label = c("Z\u00e9ro", "", "")))
  expect_identical(OECDdata:::.codes(lists[[2L]]),
    data.table::data.table(code = character(), label = character()))
  duplicate <- OECDdata:::.read_xml('<root><Codelist><Code id="x"/><Code id="x"/></Codelist></root>',
    is_file = FALSE)
  expect_error(OECDdata:::.codes(OECDdata:::.children(duplicate, "Codelist")[[1L]]),
    class = "OECDdata_metadata_error")
})

test_that("native reference extraction uses the first descendant and stable defaults", {
  doc <- OECDdata:::.read_xml(paste0('<root><Structure><wrapper><Ref agencyID="A" id="ONE"',
    ' version="1.2" maintainableParentID="CS" maintainableParentVersion="2.0"/></wrapper>',
    '<Ref agencyID="B" id="TWO"/></Structure><Structure/></root>'), is_file = FALSE)
  nodes <- OECDdata:::.children(doc, "Structure")
  expect_identical(OECDdata:::.ref(nodes[[1L]]), list(agency = "A", id = "ONE", version = "1.2",
    parent = "CS", parent_version = "2.0"))
  empty <- list(agency = "", id = "", version = "", parent = "", parent_version = "")
  expect_identical(OECDdata:::.ref(nodes[[2L]]), empty)
  expect_identical(OECDdata:::.ref(NULL), empty)
})

test_that("native and xml2 inputs produce the same structure and parsed observations", {
  native <- OECDdata:::.read_xml(fixture_path("structure.xml"), is_file = TRUE)
  invisible(lapply(c("en", "fr", "xx"), function(language) {
    local_oecd(language = language)
    expected <- fixture_structure()
    actual <- fixture_structure(doc = native)
    expect_identical(actual, expected)
    expect_identical(OECDdata:::.parse_data(fixture_path("example.csv"), actual),
      OECDdata:::.parse_data(fixture_path("example.csv"), expected))
  }))
})

test_that("public imports use native metadata on downloads and raw-cache replays", {
  text <- paste(readLines(fixture_path("structure.xml")), collapse = "\n")
  csv <- paste(readLines(fixture_path("example.csv")), collapse = "\n")
  state <- local_fake_http(statuses = rep(200L, 3L), bodies = c(text, text, csv))
  local_oecd(strings_as_factors = FALSE, return_data_table = TRUE, language = "en",
    dataset = NULL, api_version = "v2")
  catalogue <- importDataList()
  expect_s3_class(catalogue, "OECDDataList")
  expect_identical(catalogue$Code, c("TEST,DEMO,1.0", "TEST,OTHER,1.0"))
  expect_false(attr(catalogue, "Cached"))
  filters <- list(FREQ = "M", REF_AREA = c("USA", "FRA"))
  downloaded <- importData("DEMO", filters = filters)
  expected <- OECDdata:::.parse_data(fixture_path("example.csv"), fixture_structure())
  expect_identical(lapply(downloaded, identity), lapply(expected, identity))
  expect_identical(attr(downloaded, "OECDDatasetCode"), "TEST,DEMO,1.0")
  expect_false(attr(downloaded, "Cached"))
  expect_identical(state$calls, 3L)
  state$now <- state$now + 10
  local_oecd(offline = TRUE)
  replayed <- importData("DEMO", filters = filters)
  expect_identical(lapply(replayed, identity), lapply(downloaded, identity))
  expect_true(attr(replayed, "Cached"))
  expect_identical(attr(replayed, "DownloadTime"), attr(downloaded, "DownloadTime"))
  expect_identical(state$calls, 3L)
})

test_that("missing local representations still resolve concept core dictionaries", {
  doc <- fixture_doc()
  dimension <- xml2::xml_find_first(doc,
    ".//*[local-name()='Dimension' and @id='REF_AREA']")
  local <- xml2::xml_find_first(dimension, "./*[local-name()='LocalRepresentation']")
  enumeration <- xml2::xml_find_first(local, "./*[local-name()='Enumeration']")
  concept <- xml2::xml_find_first(doc,
    ".//*[local-name()='Concept' and @id='REF_AREA']")
  core <- xml2::xml_add_child(concept, "CoreRepresentation")
  xml2::xml_add_child(core, enumeration)
  xml2::xml_remove(local)
  actual <- fixture_structure(doc = doc)
  expect_identical(actual$labels$REF_AREA, fixture_structure()$labels$REF_AREA)
  expect_identical(actual$dimensions[id == "REF_AREA"]$codelist, "TEST,CL_REF_AREA,1.0")
})

test_that("native nodes retain their document after file cleanup and garbage collection", {
  path <- tempfile(fileext = ".xml")
  writeLines('<root><Codelist id="CL"><Code id="00"><Name>Kept</Name></Code></Codelist></root>', path)
  node <- local({
    doc <- OECDdata:::.read_xml(path, is_file = TRUE)
    OECDdata:::.children(doc, "Codelist")[[1L]]
  })
  unlink(path)
  invisible(gc())
  invisible(gc())
  expect_identical(OECDdata:::.attr(node, "id"), "CL")
  expect_identical(OECDdata:::.codes(node),
    data.table::data.table(code = "00", label = "Kept"))
  child <- OECDdata:::.children(node, "Code")[[1L]]
  rm(node)
  invisible(gc())
  expect_identical(OECDdata:::.localized(child), "Kept")
})

test_that("serialized native pointers are rejected instead of dereferenced", {
  doc <- OECDdata:::.read_xml('<root><Item id="kept"/></root>', is_file = FALSE)
  node <- OECDdata:::.children(doc, "Item")[[1L]]
  invalid <- unserialize(serialize(node, NULL))
  expect_error(OECDdata:::.attr(invalid, "id"))
  invalid_doc <- unserialize(serialize(doc, NULL))
  expect_error(OECDdata:::.descendants(invalid_doc, "Item"))
})

test_that("native parsing rejects malformed XML without poisoning later parses", {
  invisible(lapply(c("", "<root>", "<root><x></root>", "<root>&unknown;</root>",
    '<root a="1" a="2"/>'), function(text)
    expect_error(OECDdata:::.read_xml(text, is_file = FALSE))))
  doc <- OECDdata:::.read_xml('<root><Item id="ok"/></root>', is_file = FALSE)
  expect_identical(OECDdata:::.attr(OECDdata:::.children(doc, "Item"), "id"), "ok")
})

test_that("external entity declarations cannot disclose local files", {
  expect_error(OECDdata:::.read_xml('<!DOCTYPE root><root/>', is_file = FALSE))
  expect_error(OECDdata:::.read_xml(
    '<!DOCTYPE root [<!ENTITY ordinary "text">]><root>&ordinary;</root>', is_file = FALSE))
  path <- tempfile(fileext = ".txt")
  sentinel <- "OECDDATA_EXTERNAL_ENTITY_MUST_NOT_BE_LOADED"
  writeLines(sentinel, path)
  withr::defer(unlink(path))
  uri <- paste0("file://", if (.Platform$OS.type == "windows") "/" else "",
    normalizePath(path, winslash = "/"))
  text <- paste0('<!DOCTYPE root [<!ENTITY outside SYSTEM "', uri,
    '">]><root><Item>&outside;</Item></root>')
  doc <- tryCatch(OECDdata:::.read_xml(text, is_file = FALSE), error = identity)
  # Explicit rejection and an unexpanded entity are both safe. Standard XML
  # entities and numeric character references are exercised separately above.
  if (inherits(doc, "error")) {
    expect_match(conditionMessage(doc), "entity|entities|DTD|doctype|XML|structure", ignore.case = TRUE)
  } else {
    value <- OECDdata:::.text(OECDdata:::.children(doc, "Item"))
    expect_false(any(grepl(sentinel, value, fixed = TRUE)))
  }
})
