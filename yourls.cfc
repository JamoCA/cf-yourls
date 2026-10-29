/**
 * YOURLS API client for Adobe ColdFusion 2016+ and Lucee 5+.
 *
 * Wraps every built-in action of the YOURLS 1.10.x API (shorturl, expand, url-stats,
 * stats, db-stats, version) plus the actions added by the YOURLS-Expiry plugin
 * (expiry, expiry-stats, prune). Any other plugin action can be reached with call().
 *
 * Authentication:
 *   - username + password, or
 *   - signature, sent as a time-limited hash (default, "timestamp" mode) or raw ("plain" mode).
 *
 * Every public API method returns the same struct:
 *   success     boolean  true when YOURLS reported a 200 with no errorCode and no status "fail"
 *   statusCode  number   YOURLS statusCode/errorCode when present, otherwise the HTTP status
 *   message     string   YOURLS "message" value when present
 *   error       string   human-readable reason when success is false, otherwise ""
 *   data        struct   the full decoded JSON body (still populated on failures such as 409)
 *   raw         string   the undecoded response body
 *   request     struct   (debug or offline only) the request that was or would have been sent
 *   offline     boolean  (offline only) true
 */
component output="false" hint="YOURLS API client" {

	variables.hashAlgoMap = [
		"sha256": "SHA-256",
		"sha384": "SHA-384",
		"sha512": "SHA-512",
		"md5": "MD5"
	];
	variables.statsFilters = "top,bottom,rand,last";
	variables.expiryTypes = "click,clock";
	variables.ageMods = "min,hour,day";
	variables.pruneScopes = "expired,scrub,killall";

	/**
	 * @config.hint Keys: endpoint (required), username, password, signature, signatureMode (timestamp|plain), hashAlgo (sha256|sha384|sha512|md5), method (post|get), timeout (seconds), userAgent, offline, debug
	 */
	public any function init(required struct config) {
		var cfg = [
			"endpoint": "",
			"username": "",
			"password": "",
			"signature": "",
			"signatureMode": "timestamp",
			"hashAlgo": "sha256",
			"method": "post",
			"timeout": 20,
			"userAgent": "cf-yourls/1.0 (CFML)",
			"offline": javacast("boolean", 0),
			"debug": javacast("boolean", 0)
		];
		structAppend(cfg, arguments.config, true);
		cfg.endpoint = trim(cfg.endpoint);
		cfg.signatureMode = lcase(trim(cfg.signatureMode));
		cfg.hashAlgo = lcase(trim(cfg.hashAlgo));
		cfg.method = lcase(trim(cfg.method));
		cfg.offline = javacast("boolean", isValid("boolean", cfg.offline) && cfg.offline ? 1 : 0);
		cfg.debug = javacast("boolean", isValid("boolean", cfg.debug) && cfg.debug ? 1 : 0);

		if (!len(cfg.endpoint)) {
			throw(type = "yourls.config", message = "YOURLS config requires an endpoint, e.g. https://sho.rt/yourls-api.php");
		}
		if (!hasUserPass(cfg) && !len(trim(cfg.signature))) {
			throw(type = "yourls.config", message = "YOURLS config requires either a signature or both a username and a password");
		}
		if (!listFindNoCase("timestamp,plain", cfg.signatureMode)) {
			throw(type = "yourls.config", message = "YOURLS signatureMode must be 'timestamp' or 'plain', got '" & cfg.signatureMode & "'");
		}
		if (!structKeyExists(variables.hashAlgoMap, cfg.hashAlgo)) {
			throw(type = "yourls.config", message = "YOURLS hashAlgo must be one of " & structKeyList(variables.hashAlgoMap) & ", got '" & cfg.hashAlgo & "'");
		}
		if (!listFindNoCase("post,get", cfg.method)) {
			throw(type = "yourls.config", message = "YOURLS method must be 'post' or 'get', got '" & cfg.method & "'");
		}
		variables.config = cfg;
		return this;
	}

	/* ---------------------------------------------------------------- */
	/* Built-in YOURLS actions                                           */
	/* ---------------------------------------------------------------- */

	/**
	 * Shorten a URL. keyword and title are optional. The expiry arguments are only sent
	 * when expiry is "click" or "clock" and require the YOURLS-Expiry plugin on the server.
	 */
	public struct function shorturl(
		required string url,
		string keyword = "",
		string title = "",
		string expiry = "",
		numeric count = 0,
		numeric age = 0,
		string ageMod = "",
		string postx = ""
	) {
		var params = [:];
		var longUrl = trim(arguments.url);
		if (!len(longUrl)) {
			throw(type = "yourls.invalidArgument", message = "shorturl requires a url to shorten");
		}
		params["url"] = longUrl;
		if (len(trim(arguments.keyword))) {
			params["keyword"] = trim(arguments.keyword);
		}
		if (len(trim(arguments.title))) {
			params["title"] = trim(arguments.title);
		}
		if (len(trim(arguments.expiry))) {
			structAppend(params, buildExpiryParams(arguments.expiry, arguments.count, arguments.age, arguments.ageMod, arguments.postx, javacast("boolean", 0)), true);
		}
		return call("shorturl", params);
	}

	/**
	 * Get the long URL behind a short URL. Accepts a keyword ("abc") or a full short URL ("https://sho.rt/abc").
	 */
	public struct function expand(required string shorturl) {
		return call("expand", ["shorturl": requireShortUrl(arguments.shorturl, "expand")]);
	}

	/**
	 * Get click statistics for one short URL.
	 */
	public struct function urlStats(required string shorturl) {
		return call("url-stats", ["shorturl": requireShortUrl(arguments.shorturl, "urlStats")]);
	}

	/**
	 * Get a list of links. filter is one of top, bottom, rand, last.
	 */
	public struct function stats(string filter = "top", numeric limit = 10, numeric start = 0) {
		var params = [:];
		var filterName = lcase(trim(arguments.filter));
		if (!listFind(variables.statsFilters, filterName)) {
			throw(type = "yourls.invalidArgument", message = "stats filter must be one of " & variables.statsFilters & ", got '" & arguments.filter & "'");
		}
		if (arguments.limit lte 0) {
			throw(type = "yourls.invalidArgument", message = "stats limit must be greater than zero");
		}
		params["filter"] = filterName;
		params["limit"] = javacast("int", arguments.limit);
		if (arguments.start gt 0) {
			params["start"] = javacast("int", arguments.start);
		}
		return call("stats", params);
	}

	/**
	 * Get the global link and click counts.
	 */
	public struct function dbStats() {
		return call("db-stats");
	}

	/**
	 * Get the YOURLS version. Pass db=true to include the database schema version.
	 */
	public struct function version(boolean db = false) {
		var params = [:];
		if (arguments.db) {
			params["db"] = javacast("int", 1);
		}
		return call("version", params);
	}

	/* ---------------------------------------------------------------- */
	/* YOURLS-Expiry plugin actions                                      */
	/* ---------------------------------------------------------------- */

	/**
	 * Set an expiry on an existing short URL. expiry is "click" (needs count) or "clock" (needs age and ageMod).
	 */
	public struct function expiry(
		required string shorturl,
		required string expiry,
		numeric count = 0,
		numeric age = 0,
		string ageMod = "",
		string postx = ""
	) {
		var params = ["shorturl": requireShortUrl(arguments.shorturl, "expiry")];
		structAppend(params, buildExpiryParams(arguments.expiry, arguments.count, arguments.age, arguments.ageMod, arguments.postx, javacast("boolean", 1)), true);
		return call("expiry", params);
	}

	/**
	 * Get the expiry details for one short URL.
	 */
	public struct function expiryStats(required string shorturl) {
		return call("expiry-stats", ["shorturl": requireShortUrl(arguments.shorturl, "expiryStats")]);
	}

	/**
	 * Housekeeping. scope is "expired" (delete expired links), "scrub" (remove all expiry data) or "killall" (expire every perishable link now).
	 */
	public struct function prune(string scope = "expired") {
		var scopeName = lcase(trim(arguments.scope));
		if (!listFind(variables.pruneScopes, scopeName)) {
			throw(type = "yourls.invalidArgument", message = "prune scope must be one of " & variables.pruneScopes & ", got '" & arguments.scope & "'");
		}
		return call("prune", ["scope": scopeName]);
	}

	/* ---------------------------------------------------------------- */
	/* Generic plumbing                                                  */
	/* ---------------------------------------------------------------- */

	/**
	 * Call any API action, including ones added by plugins this component does not know about.
	 */
	public struct function call(required string action, struct params = {}) {
		var actionName = trim(arguments.action);
		var req = "";
		var raw = "";
		var result = "";
		if (!len(actionName)) {
			throw(type = "yourls.invalidArgument", message = "call requires an action name");
		}
		req = buildRequest(actionName, arguments.params);
		if (variables.config.offline) {
			return [
				"success": javacast("boolean", 1),
				"statusCode": javacast("int", 200),
				"message": "offline",
				"error": "",
				"data": [:],
				"raw": "",
				"offline": javacast("boolean", 1),
				"request": req
			];
		}
		raw = this.send(req);
		result = normalizeResponse(raw.statusCode, raw.fileContent);
		if (variables.config.debug) {
			result["request"] = redactRequest(req);
		}
		return result;
	}

	/**
	 * Build the outbound request: endpoint, method and the full parameter set (auth, action, format, action params).
	 */
	public struct function buildRequest(required string action, struct params = {}) {
		var outbound = [:];
		var key = "";
		for (key in arguments.params) {
			outbound[key] = arguments.params[key];
		}
		structAppend(outbound, buildAuthParams(), true);
		outbound["action"] = trim(arguments.action);
		outbound["format"] = "json";
		return [
			"endpoint": variables.config.endpoint,
			"method": variables.config.method,
			"params": outbound
		];
	}

	/**
	 * Build the authentication parameters. Pass a unix timestamp to make the hashed signature deterministic (tests).
	 */
	public struct function buildAuthParams(numeric timestamp = 0) {
		var params = [:];
		var unixTime = 0;
		if (hasUserPass(variables.config)) {
			params["username"] = variables.config.username;
			params["password"] = variables.config.password;
			return params;
		}
		if (variables.config.signatureMode eq "plain") {
			params["signature"] = trim(variables.config.signature);
			return params;
		}
		unixTime = (arguments.timestamp gt 0) ? int(arguments.timestamp) : int(getTickCount() / 1000);
		params["timestamp"] = javacast("long", unixTime);
		params["signature"] = signatureFor(unixTime);
		params["hash"] = variables.config.hashAlgo;
		return params;
	}

	/**
	 * Hash the timestamp and secret signature the way yourls_check_signature_timestamp() expects: hash(timestamp . signature), lowercase hex.
	 */
	public string function signatureFor(required numeric timestamp) {
		var algo = variables.hashAlgoMap[variables.config.hashAlgo];
		return lcase(hash(javacast("string", int(arguments.timestamp)) & trim(variables.config.signature), algo, "UTF-8"));
	}

	/**
	 * Turn a raw HTTP status line and body into the uniform result struct.
	 */
	public struct function normalizeResponse(required string statusCode, required string fileContent) {
		var httpCode = val(listFirst(trim(arguments.statusCode) & " ", " "));
		var body = trim(arguments.fileContent);
		var data = "";
		var code = httpCode;
		var message = "";
		var isSuccess = javacast("boolean", 0);
		var hasErrorCode = javacast("boolean", 0);
		var result = [
			"success": javacast("boolean", 0),
			"statusCode": javacast("int", httpCode),
			"message": "",
			"error": "",
			"data": [:],
			"raw": arguments.fileContent
		];
		if (!len(body) || !isJSON(body)) {
			result["error"] = "Non-JSON response from YOURLS (" & (len(trim(arguments.statusCode)) ? trim(arguments.statusCode) : "no status") & ")";
			return result;
		}
		data = deserializeJSON(body);
		if (!isStruct(data)) {
			// Every YOURLS action answers with a JSON object. An empty array means a plugin
			// returned null from shunt_add_new_link / add_new_link, so nothing happened.
			result["data"] = ["value": data];
			result["error"] = "Unexpected response from YOURLS: expected a JSON object, got " & left(body, 200);
			return result;
		}
		result["data"] = trimKeys(data);
		data = result.data;
		// YOURLS 1.10.x sends "errorCode":"" and "code":"" on a successful shorturl, so only a
		// non-empty errorCode counts as an error.
		hasErrorCode = structKeyExists(data, "errorCode") && isSimpleValue(data.errorCode) && len(trim(data.errorCode));
		if (hasErrorCode && isNumeric(data.errorCode)) {
			code = int(data.errorCode);
		} else if (structKeyExists(data, "statusCode") && isNumeric(data.statusCode)) {
			code = int(data.statusCode);
		}
		if (structKeyExists(data, "message") && isSimpleValue(data.message)) {
			message = data.message;
		}
		isSuccess = !hasErrorCode
			&& code eq 200
			&& !(structKeyExists(data, "status") && isSimpleValue(data.status) && data.status eq "fail");
		result["statusCode"] = javacast("int", code);
		result["message"] = message;
		result["success"] = javacast("boolean", isSuccess ? 1 : 0);
		if (!isSuccess) {
			result["error"] = len(message) ? message : "YOURLS request failed (status " & code & ")";
		}
		return result;
	}

	/**
	 * The only method that touches the network. Override or mock it to test without a server.
	 */
	public struct function send(required struct req) {
		var httpResult = {};
		var paramType = (arguments.req.method eq "get") ? "url" : "formfield";
		var key = "";
		cfhttp(
			url = arguments.req.endpoint,
			method = arguments.req.method,
			timeout = variables.config.timeout,
			useragent = variables.config.userAgent,
			getasbinary = "never",
			charset = "utf-8",
			redirect = false,
			throwonerror = false,
			result = "httpResult"
		) {
			for (key in arguments.req.params) {
				cfhttpparam(type = paramType, name = key, value = arguments.req.params[key]);
			}
		}
		return [
			"statusCode": structKeyExists(httpResult, "statusCode") ? httpResult.statusCode : "",
			"fileContent": structKeyExists(httpResult, "fileContent") ? toString(httpResult.fileContent) : ""
		];
	}

	/**
	 * The effective configuration with secrets removed.
	 */
	public struct function getConfig() {
		var cfg = duplicate(variables.config);
		structDelete(cfg, "password");
		structDelete(cfg, "signature");
		return cfg;
	}

	/* ---------------------------------------------------------------- */
	/* Private helpers                                                   */
	/* ---------------------------------------------------------------- */

	private boolean function hasUserPass(required struct cfg) {
		return len(trim(arguments.cfg.username)) && len(arguments.cfg.password);
	}

	private string function requireShortUrl(required string shorturl, required string methodName) {
		var value = trim(arguments.shorturl);
		if (!len(value)) {
			throw(type = "yourls.invalidArgument", message = arguments.methodName & " requires a shorturl (keyword or full short URL)");
		}
		return value;
	}

	/**
	 * Validate and assemble the YOURLS-Expiry plugin parameters. strict=true (expiry action) requires
	 * count or age/ageMod to be supplied; strict=false (shorturl) lets the server apply its defaults.
	 */
	private struct function buildExpiryParams(
		required string expiry,
		required numeric count,
		required numeric age,
		required string ageMod,
		required string postx,
		required boolean strict
	) {
		var params = [:];
		var expiryType = lcase(trim(arguments.expiry));
		var ageModName = lcase(trim(arguments.ageMod));
		if (!listFind(variables.expiryTypes, expiryType)) {
			throw(type = "yourls.invalidArgument", message = "expiry must be one of " & variables.expiryTypes & ", got '" & arguments.expiry & "'");
		}
		params["expiry"] = expiryType;
		if (expiryType eq "click") {
			if (arguments.count gt 0) {
				params["count"] = javacast("int", arguments.count);
			} else if (arguments.strict) {
				throw(type = "yourls.invalidArgument", message = "click expiry requires a count greater than zero");
			}
		} else {
			if (arguments.age gt 0) {
				params["age"] = javacast("int", arguments.age);
			} else if (arguments.strict) {
				throw(type = "yourls.invalidArgument", message = "clock expiry requires an age greater than zero");
			}
			if (len(ageModName)) {
				if (!listFind(variables.ageMods, ageModName)) {
					throw(type = "yourls.invalidArgument", message = "ageMod must be one of " & variables.ageMods & ", got '" & arguments.ageMod & "'");
				}
				params["ageMod"] = ageModName;
			} else if (arguments.strict) {
				throw(type = "yourls.invalidArgument", message = "clock expiry requires an ageMod of " & variables.ageMods);
			}
		}
		if (len(trim(arguments.postx))) {
			params["postx"] = trim(arguments.postx);
		}
		return params;
	}

	/**
	 * Trim whitespace from top-level response keys. The Expiry plugin's "no expiry data" reply
	 * has a literal "expiry\t\t" key (a typo in its plugin.php), which this turns back into "expiry".
	 */
	private struct function trimKeys(required struct data) {
		var cleaned = [:];
		var key = "";
		for (key in arguments.data) {
			cleaned[trim(key)] = arguments.data[key];
		}
		return cleaned;
	}

	private struct function redactRequest(required struct req) {
		var copy = duplicate(arguments.req);
		if (structKeyExists(copy.params, "password")) {
			copy.params["password"] = "***";
		}
		return copy;
	}

}
