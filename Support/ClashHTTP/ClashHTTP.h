#include <curl/curl.h>

// Swift cannot call libcurl's variadic setters directly.
static inline CURLcode clash_get(const char *url, const char *socket_path, const char *proxy,
                                 long limit, curl_write_callback write_body, void *context,
                                 curl_xferinfo_callback progress, long *status) {
    CURL *curl = curl_easy_init();
    if (!curl) return CURLE_FAILED_INIT;
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_UNIX_SOCKET_PATH, socket_path);
    curl_easy_setopt(curl, CURLOPT_PROXY, proxy);
    curl_easy_setopt(curl, CURLOPT_NOPROXY, socket_path ? "*" : "");
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, socket_path ? 5000L : 8000L);
    curl_easy_setopt(curl, CURLOPT_MAXFILESIZE, limit);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_body);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, context);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, progress);
    CURLcode result = curl_easy_perform(curl);
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, status);
    curl_easy_cleanup(curl);
    return result;
}
