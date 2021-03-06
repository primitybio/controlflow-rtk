pkg.env = new.env()

# Set your development base url in .Renviron in the package directory
pkg.env$baseURL = Sys.getenv("CELLENGINE_API_URL", "https://cellengine.com/api/v1")

handleResponse = function(response) {
  httr::warn_for_status(response)
  content = httr::content(response, "text", encoding = "UTF-8")
  return(jsonlite::fromJSON(content))
}

ua = (function (){
  versions <- c(
    `CellEngine API Toolkit` = "0.1.0", # TODO see if utils::packageVersion works
    libcurl = curl::curl_version()$version,
    `r-curl` = as.character(utils::packageVersion("curl")),
    httr = as.character(utils::packageVersion("httr")))
  paste0(names(versions), "/", versions, collapse = " ")
})()

ensureBaseUrl = function() {
  if (pkg.env$baseURL == "") stop("Please call setServer(host) first.")
}

baseGet = function(url, params = list()) {
  ensureBaseUrl()
  fullURL = paste(pkg.env$baseURL, url, sep = "/")
  handleResponse(httr::GET(fullURL, query = params, httr::user_agent(ua)))
}

basePatch = function(url, body, params = list()) {
  ensureBaseUrl()
  fullURL = paste(pkg.env$baseURL, url, sep = "/")
  handleResponse(httr::PATCH(fullURL, body = body, query = params, httr::content_type_json(), httr::user_agent(ua)))
}

basePut = function(url, body, params = list()) {
  ensureBaseUrl()
  fullURL = paste(pkg.env$baseURL, url, sep = "/")
  handleResponse(httr::PUT(fullURL, body = body, query = params, httr::content_type_json(), httr::user_agent(ua)))
}

basePost = function(url, body, params = list()) {
  ensureBaseUrl()
  fullURL = paste(pkg.env$baseURL, url, sep = "/")
  handleResponse(httr::POST(fullURL, body = body, query = params, httr::content_type_json(), httr::user_agent(ua)))
}

baseDelete = function(url, params = list()) {
  ensureBaseUrl()
  fullURL = paste(pkg.env$baseURL, url, sep = "/")
  response = httr::DELETE(fullURL, query = params, httr::user_agent(ua))
  httr::warn_for_status(response)
}

checkDefined = function(param) {
  if (is.null(param)) {
    stop(paste0("parameter '", deparse(substitute(param)), "' is NULL"))
  }
}

#' No compensation.
#'
#' A constant representing no compensation.
#'
#' @export
UNCOMPENSATED = 0

#' File-internal compensation.
#'
#' A constant representing file-internal compensation.
#'
#' @export
FILE_INTERNAL = -1

#' Ungated.
#'
#' A constant representing the ungated population.
#'
#' @export
UNGATED = ""

#' Returns more information about the last error.
#'
#' Some functions in this package will store additional error information so
#' that it is retrievable using \code{getErrorInfo()}.
#'
#' @export
getErrorInfo = function() {
  pkg.env$lastError
}

#' Resource By Name
#'
#' Allows specifying a resource by name instead of by id, anywhere that an id is
#' accepted.
#'
#' Internally, this looks up the resource's id by name before the function runs.
#' To improve performance, the resource's id is cached for the duration of the R
#' session. Resources such as gates that exist within an experiment are cached
#' within the experiment's scope. That is, the following is safe, even though
#' the FCS files have the same name:
#'
#' \code{
#' getFcsFile(byName("experiment 1"), byName("fcsfile1.fcs"))
#' getFcsFile(byName("experiment 2"), byName("fcsfile1.fcs"))
#' }
#'
#' @param name Name of resource.
#' @examples
#' \dontrun{
#' getGates(byName("my experiment"))
#' getGates(experimentId = byName("my experiment"))
#' }
#' @export
byName = function(name) {
  class(name) <- "_boxed_by_name"
  name
}

byNameHash = new.env(hash = TRUE, parent = emptyenv())

lookupByName = function(listpath, name, prop = "name") {
  if (class(name) != "_boxed_by_name") return(name)
  name = unclass(name)

  key = paste(listpath, name, sep="$$$")
  if (exists(key, envir = byNameHash)) return(get(key, envir = byNameHash))

  vals = baseGet(listpath, params = list(
    query = sprintf("eq(%s, \"%s\")", prop, name),
    limit = 2 # need >1 so we can detect ambiguous matches
  ))
  if (!is.data.frame(vals)) {
    stop(sprintf("Resource with the name '%s' does not exist.", name))
  }
  if (nrow(vals) > 1) {
    stop(sprintf("More than one resource with the name '%s' exists.", name))
  }

  val = vals$`_id`
  assign(key, val, envir = byNameHash)
  val
}

#' Find a Resource By Name
#'
#' Allows creation of a by-name lookup object per experiment, which can
#' then be used to find resources by name instead of id. The resource's id is
#' cached for the duration of the R session.
#' If a name is not specified, a list of all requested resources will be returned.
#'
#' @param experimentId Experiment to create lookup for.
#' @return A function that takes the parameters "resource" and "name":
#'   resource Type of resource. Available options are "gates", "populations", "fcsfiles", and "compensations".
#'   name Name of resource to search for.
#' @examples
#' \dontrun{
#' lookup = createLookup("5e1f66a06f5f3f0759b479c9")
#' lookup("gates", "test_gate")
#' # or:
#' lookup("gates")
#' }
#' @export
createLookup <- function(experimentId) {
  function(resource, name='') {
    allowedArgs = c("gates", "populations", "fcsfiles", "compensations")
    if (resource %in% allowedArgs == FALSE) {
      stop(sprintf("Resource must be one of %s", paste(allowedArgs, collapse = ", ")))
    }
    listpath = sprintf("experiments/%s/%s", experimentId, resource)

    if (name == '') {
      data = baseGet(listpath)

    } else {
      args <- list(listpath=listpath, name=byName(name))
      if (resource == "fcsfiles") {
        args <- c(args, list(prop = "filename"))
      }
      id = do.call(lookupByName, args)
      data = baseGet(sprintf("%s/%s/", listpath, id))
    }
    data
  }
}
