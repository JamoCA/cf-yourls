# cf-yourls

A ColdFusion component for the [YOURLS](https://yourls.org/) URL shortener API. It covers every built-in action in YOURLS 1.10.x, the three actions added by the [YOURLS-Expiry](https://github.com/joshp23/YOURLS-Expiry) plugin, and a generic `call()` for any other plugin action.

Tested on Adobe ColdFusion 2016 and Lucee 6 with TestBox 4.x. No dependencies beyond `cfhttp`.

## Quick start

```cfc
yourls = new yourls([
	"endpoint":  "https://sho.rt/yourls-api.php",
	"signature": "your-32-char-signature"
]);

result = yourls.shorturl("https://www.mycfml.com/", "mycfml", "My CFML blog");
if (result.success) {
	writeOutput(result.data.shorturl);
} else {
	writeOutput(result.statusCode & ": " & result.error);
}
```

Or with a username and password:

```cfc
yourls = new yourls([
	"endpoint": "https://sho.rt/yourls-api.php",
	"username": "admin",
	"password": "secret"
]);
```

## Configuration

| Key | Default | Notes |
|---|---|---|
| `endpoint` | required | Full URL of `yourls-api.php`. |
| `username`, `password` | `""` | Used when both are present. Takes priority over `signature`. |
| `signature` | `""` | Your API signature from the YOURLS admin Tools page. |
| `signatureMode` | `timestamp` | `timestamp` sends `hash(timestamp + signature)` with the timestamp, which YOURLS accepts for 12 hours and which never exposes the signature itself. `plain` sends the raw signature. |
| `hashAlgo` | `sha256` | `sha256`, `sha384`, or `sha512` for YOURLS 1.10.5+. Use `md5` for older installs. |
| `method` | `post` | `post` sends form fields, `get` sends a query string. |
| `timeout` | `20` | Seconds. |
| `userAgent` | `cf-yourls/1.0 (CFML)` | |
| `debug` | `false` | Adds the outbound request (password redacted) to every result. |
| `offline` | `false` | Skips the network and returns the request that would have been sent. Used by the unit tests. |

## Methods

Built-in YOURLS actions:

| Method | YOURLS action | Arguments |
|---|---|---|
| `shorturl(url, keyword, title, expiry, count, age, ageMod, postx)` | `shorturl` | Only `url` is required. The expiry arguments need the Expiry plugin. |
| `expand(shorturl)` | `expand` | A keyword or a full short URL. |
| `urlStats(shorturl)` | `url-stats` | |
| `stats(filter, limit, start)` | `stats` | `filter` is `top`, `bottom`, `rand`, or `last`. Default `top`, 10. |
| `dbStats()` | `db-stats` | |
| `version(db)` | `version` | Pass `true` to include the database schema version. |

Expiry plugin actions:

| Method | YOURLS action | Arguments |
|---|---|---|
| `expiry(shorturl, expiry, count, age, ageMod, postx)` | `expiry` | `expiry` is `click` (with `count`) or `clock` (with `age` and `ageMod` of `min`, `hour`, or `day`). `postx` is the URL to redirect to after expiration. |
| `expiryStats(shorturl)` | `expiry-stats` | |
| `prune(scope)` | `prune` | `expired` (default), `scrub`, or `killall`. |

Anything else:

```cfc
result = yourls.call("some-plugin-action", ["foo": "bar"]);
```

Bad argument values (an unknown stats filter, an empty URL, an expiry type other than click or clock) throw `yourls.invalidArgument` before any request is sent. Bad configuration throws `yourls.config` from `init()`.

## Result struct

Every method returns the same shape:

| Key | Type | Meaning |
|---|---|---|
| `success` | boolean | `true` when YOURLS answered 200 with no `errorCode` and no `status: "fail"`. |
| `statusCode` | number | The `statusCode` or `errorCode` from the JSON body, otherwise the HTTP status. |
| `message` | string | The `message` field from YOURLS, if any. |
| `error` | string | Why `success` is false. Empty on success. |
| `data` | struct | The complete decoded JSON body. |
| `raw` | string | The undecoded body, for debugging. |

`data` is populated on failures too. When you shorten a URL that already exists on an install that enforces unique long URLs (`YOURLS_UNIQUE_URLS`, the default), YOURLS answers 409 and `success` is false, but `data.shorturl` still holds the existing short URL. An install that allows duplicates answers 200 and creates another short URL instead:

```cfc
result = yourls.shorturl("https://www.mycfml.com/");
if (result.success || result.statusCode eq 409) {
	shortUrl = result.data.shorturl;
}
```

## Running the tests

```
box install
box server start
```

Then open `http://127.0.0.1:8921/tests/runner.cfm`. The unit specs run entirely offline.

For a smoke test against a real install, copy `config.example.json` to `config.json` (gitignored), fill in the endpoint and credentials, and open `http://127.0.0.1:8921/tests/live.cfm`. Read-only actions run by default. Set `"allowWrites": true` to also create one test link with a timestamped keyword and put a click expiry on it.

## Troubleshooting

**`shorturl` returns `success: false` with "Unexpected response from YOURLS: expected a JSON object, got []".** The server answered with an empty array and no link was created. YOURLS 1.10.x only does that when an installed plugin returns null from the `shunt_add_new_link` or `add_new_link` filter during an API call. Authentication is fine at that point (a bad signature gets a 403 "Please log in" instead), and the other actions keep working. Check the active plugins on the server, or try adding the same URL through the admin page to see whether the plugin reports an error there.

**Expiry methods return 400 "Unknown or missing action parameter".** YOURLS answers that for any action it does not recognize, so it means the Expiry plugin is not installed or not active on the server. The built-in actions keep working.

**`expiryStats` data has an `expiry` key for a link with no expiry.** The Expiry plugin's own source emits that key as `"expiry\t\t"` (two literal tabs, a typo in its `plugin.php`). The component trims whitespace from response keys so you can read `data.expiry` either way.

## Notes on the signature

CFML's `hash()` returns uppercase hex and PHP's `hash_equals()` is case sensitive, so the component lowercases the digest. YOURLS checks `hash(timestamp . signature)` and `hash(signature . timestamp)`, and this component sends the first form. The timestamp is the Unix time in seconds from `getTickCount()`, so the server and client clocks need to agree to within the 12-hour nonce life.

## License

MIT
